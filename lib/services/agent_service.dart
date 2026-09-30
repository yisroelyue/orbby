import 'dart:async';
import '../agent/agent_ws_client.dart';
import '../agent/types.dart' as agent_types;
import '../config/settings.dart';
import '../config/platform.dart';
import '../models/agent_question.dart';
import '../models/chat_attachment.dart';
import 'personality_service.dart';

class AgentService {
  AgentService._();
  static final AgentWsClient _client = AgentWsClient();
  /// 默认会话（未显式传 sessionId 的调用兜底）；多会话 tab 各自持有
  /// 独立的 agentSessionId（见 [newSessionId]），显式传入优先
  static String _sessionId = 'default';
  /// 会话 → 进行中的 requestId（多会话并发各自可取消，互不顶掉）
  static final _activeRequests = <String, String>{};
  static String get sessionId => _sessionId;

  /// 生成新的 agent 会话 ID（Node 侧会话隔离 key：上下文/工作区/锁）
  static String newSessionId() =>
      'session-${DateTime.now().microsecondsSinceEpoch}';

  /// Node 侧主动推送（非请求-响应）的事件流（如 skills.changed 技能目录
  /// 变化通知）。订阅方自行按 type 过滤，listen 必须带 onError 容忍断连
  /// （broadcast 流的错误会发给所有订阅者，不吞会炸 zone）
  static Stream<Map<String, dynamic>> get serverEvents => _client.events;

  /// 取消指定会话当前进行中的请求；不传 sessionId 取默认会话
  static void cancelCurrent({String? sessionId}) {
    final sid = sessionId ?? _sessionId;
    final requestId = _activeRequests[sid];
    if (requestId == null) return;
    _client.send('chat.cancel', requestId, const {}, sid);
  }

  static void setSystemPrompt(String? prompt) {}
  static void setPermissionMode(String mode) { _permissionMode = mode; _client.send('permission.mode', _id(), {'mode': mode}, _sessionId); }
  static Future<Map<String, dynamic>> permissionStatus() async {
    final result = await _client.request('permission.status', _id(), sessionId: _sessionId);
    return Map<String, dynamic>.from((result['payload'] as Map?) ?? const {});
  }

  /// 会话工作区（Node 侧解析后的绝对路径）
  static Future<String> workspaceStatus({String? sessionId}) async {
    final result = await _client.request('workspace.get', _id(), sessionId: sessionId ?? _sessionId);
    return ((result['payload'] as Map?)?['workspace'] ?? '').toString();
  }

  /// 切换工作区；相对路径由 Node 侧按该会话当前工作区解析，目录不存在会抛错
  static Future<String> setWorkspace(String path, {String? sessionId}) async {
    final result = await _client.request('workspace.set', _id(), sessionId: sessionId ?? _sessionId, payload: {'path': path});
    return ((result['payload'] as Map?)?['workspace'] ?? '').toString();
  }

  /// 重载技能：清 Node 侧技能缓存（面板侧重扫由 HomeScreen 完成），
  /// 下次 @ 引用展开时按目录现状重扫——加/改技能文件无需重启应用
  static Future<void> reloadSkills({String? sessionId}) async {
    await _client.request('skills.reload', _id(), sessionId: sessionId ?? _sessionId);
  }

  /// Compatibility hook retained for callers from the pre-WebSocket Agent.
  /// Logging is owned by the Node runtime now and is sent with future runtime
  /// configuration messages rather than mutating a Dart Agent instance.
  static Future<void> syncLogSettings() async {}

  static Future<String> chat(String text, {String mode = 'accept', List<Map<String, String>> history = const [], String? sessionId}) async {
    final sid = sessionId ?? _sessionId;
    final id = _id();
    _activeRequests[sid] = id;
    try {
      final result = await _client.request('chat.start', id, sessionId: sid, payload: {'message': text, 'mode': mode, 'history': history, 'llm': await _llmPayload()});
      return ((result['payload'] as Map?)?['content'] ?? '').toString();
    } finally {
      if (_activeRequests[sid] == id) _activeRequests.remove(sid);
    }
  }

  static Stream<AgentStreamEvent> chatStream(String text, {String mode = 'accept', List<Map<String, String>> history = const [], String? conversationId, List<ChatAttachment> attachments = const [], String? sessionId, void Function(Map<String, dynamic>)? onEvent}) async* {
    final sid = sessionId ?? _sessionId;
    final id = _id();
    _activeRequests[sid] = id;
    await _client.connect();
    final queue = StreamController<AgentStreamEvent>();
    final subscription = _client.events.where((e) => e['requestId'] == id).listen((event) {
      onEvent?.call(event);
      switch (event['type']) {
        case 'agent.token': queue.add(AgentTokenEvent(((event['payload'] as Map)['text'] ?? '').toString()));
        case 'agent.round': queue.add(AgentRoundEvent((event['payload'] as Map)['round'] as int));
        case 'step.start': queue.add(AgentRoundEvent(((event['payload'] as Map)['step'] ?? 0) as int));
        case 'user.question': queue.add(AgentQuestionEvent(((event['payload'] as Map)['questionId'] ?? '').toString(), (((event['payload'] as Map)['questions'] as List?) ?? const []).map(AgentQuestion.fromJson).toList()));
        case 'tool.start': queue.add(AgentToolEvent(((event['payload'] as Map)['id'] ?? '').toString(), ((event['payload'] as Map)['name'] ?? 'tool').toString(), true, details: (event['payload'] as Map)['arguments']));
        case 'tool.result': queue.add(AgentToolEvent(((event['payload'] as Map)['id'] ?? '').toString(), ((event['payload'] as Map)['name'] ?? 'tool').toString(), false, details: (event['payload'] as Map)['output'], changes: (event['payload'] as Map)['changes']));
        case 'tool.error': queue.add(AgentToolEvent(((event['payload'] as Map)['id'] ?? '').toString(), ((event['payload'] as Map)['name'] ?? 'tool').toString(), false, error: true, details: (event['payload'] as Map)['message']));
        case 'agent.done': queue.close();
        case 'agent.error': queue.addError(Exception((event['error'] as Map)['message'])); queue.close();
      }
    }, onError: (Object error, StackTrace stack) { if (!queue.isClosed) { queue.addError(error, stack); queue.close(); } }, onDone: () { if (!queue.isClosed) { queue.addError(AgentException('Agent 服务连接已断开')); queue.close(); } });
    final payload = await chatPayload(text, mode: mode, history: history, attachments: attachments);
    if (conversationId != null) payload['conversationId'] = conversationId;
    _client.send('chat.start', id, payload, sid);
    try { yield* queue.stream; } finally {
      // 值匹配才清：同会话新请求已顶掉旧登记时不误删
      if (_activeRequests[sid] == id) _activeRequests.remove(sid);
      await subscription.cancel(); if (!queue.isClosed) await queue.close();
    }
  }

  static Future<Map<String, dynamic>> chatPayload(String text, {String mode = 'accept', List<Map<String, String>> history = const [], List<ChatAttachment> attachments = const []}) async {
    return {
      'message': text,
      'mode': mode,
      'permissionMode': _permissionMode,
      'history': history,
      // 附件 payload（含 Base64）由 ChatAttachmentController.ensurePayload 预先填好
      if (attachments.isNotEmpty)
        'attachments': [
          for (final a in attachments)
            if (a.sendPayload != null) a.sendPayload!,
        ],
      'llm': await _llmPayload(),
    };
  }

  /// 重置（删除）Node 侧该会话的内存上下文；下次 chat 惰性重建。
  /// 多会话下必须带 sessionId，否则会把默认会话重置掉
  static void resetConversation({String? sessionId}) { final id = _id(); _client.send('session.reset', id, const {}, sessionId ?? _sessionId); }

  static Future<String> compact({String? sessionId}) async {
    final result = await _client.request('agent.compact', _id(), sessionId: sessionId ?? _sessionId, payload: {'llm': await _llmPayload()});
    return ((result['payload'] as Map?)?['content'] ?? '').toString();
  }

  static Future<Map<String, dynamic>> status({String? sessionId}) async {
    final result = await _client.request('session.stats', _id(), sessionId: sessionId ?? _sessionId);
    return Map<String, dynamic>.from((result['payload'] as Map?) ?? const {});
  }

  static agent_types.ConversationStats? getConversationStats() => null;
  static List<Map<String, dynamic>> getAvailableTools() => const [];
  static String _id() => 'req-${DateTime.now().microsecondsSinceEpoch}';
  static String _permissionMode = 'ask';
  static void answerQuestion(String questionId, Object answers, {String? sessionId}) => _client.send('user.answer', _id(), {'questionId': questionId, 'answers': answers}, sessionId ?? _sessionId);
  static Future<Map<String, dynamic>> _llmPayload() async {
    final settings = await SettingsService.load();
    final url = settings.chatUrl.isEmpty ? PlatformConfig.defaultChatUrl(settings.platform) : settings.chatUrl.trim();
    final model = settings.model.isEmpty ? PlatformConfig.defaultChatModel(settings.platform) : settings.model;
    return {
      'url': url,
      'apiKey': settings.apiKey,
      'model': model,
      // provider 类型由 Flutter 侧告知（Node 不解析平台配置）
      'platform': settings.platform,
      'systemPrompt': '${settings.agentSystemPrompt}\n[personality:${await PersonalityService.load()}]',
      'usageRules': settings.agentUsageRules,
      'personality': await PersonalityService.load(),
    };
  }
}

sealed class AgentStreamEvent {}
class AgentTokenEvent extends AgentStreamEvent { AgentTokenEvent(this.text); final String text; }
class AgentRoundEvent extends AgentStreamEvent { AgentRoundEvent(this.round); final int round; }
class AgentQuestionEvent extends AgentStreamEvent { AgentQuestionEvent(this.questionId, this.questions); final String questionId; final List<AgentQuestion> questions; }
class AgentToolEvent extends AgentStreamEvent { AgentToolEvent(this.id, this.name, this.running, {this.error = false, this.details, this.changes}); final String id; final String name; final bool running; final bool error; final dynamic details; final dynamic changes; }
class AgentException implements Exception { AgentException(this.message); final String message; @override String toString() => message; }
