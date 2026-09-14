import 'dart:async';
import '../agent/agent_ws_client.dart';
import '../agent/types.dart' as agent_types;
import '../config/settings.dart';
import '../config/platform.dart';
import '../models/agent_question.dart';
import '../models/chat_attachment.dart';

class AgentService {
  AgentService._();
  static final AgentWsClient _client = AgentWsClient();
  static String _sessionId = 'default';
  static String? _activeRequestId;
  static String get sessionId => _sessionId;

  static void cancelCurrent() {
    final requestId = _activeRequestId;
    if (requestId == null) return;
    _client.send('chat.cancel', requestId, const {}, _sessionId);
  }

  static void setSystemPrompt(String? prompt) {}

  /// Compatibility hook retained for callers from the pre-WebSocket Agent.
  /// Logging is owned by the Node runtime now and is sent with future runtime
  /// configuration messages rather than mutating a Dart Agent instance.
  static Future<void> syncLogSettings() async {}

  static Future<String> chat(String text, {String mode = 'accept', List<Map<String, String>> history = const []}) async {
    final id = _id();
    _activeRequestId = id;
    final result = await _client.request('chat.start', id, sessionId: _sessionId, payload: {'message': text, 'mode': mode, 'history': history, 'llm': await _llmPayload()});
    return ((result['payload'] as Map?)?['content'] ?? '').toString();
  }

  static Stream<AgentStreamEvent> chatStream(String text, {String mode = 'accept', List<Map<String, String>> history = const [], String? conversationId, List<ChatAttachment> attachments = const [], void Function(Map<String, dynamic>)? onEvent}) async* {
    final id = _id();
    _activeRequestId = id;
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
    _client.send('chat.start', id, payload, _sessionId);
    try { yield* queue.stream; } finally {
      if (_activeRequestId == id) _activeRequestId = null;
      await subscription.cancel(); if (!queue.isClosed) await queue.close();
    }
  }

  static Future<Map<String, dynamic>> chatPayload(String text, {String mode = 'accept', List<Map<String, String>> history = const [], List<ChatAttachment> attachments = const []}) async {
    return {
      'message': text,
      'mode': mode,
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

  static void resetConversation() { final id = _id(); _client.send('session.reset', id, const {}, _sessionId); }

  static Future<String> compact() async {
    final result = await _client.request('agent.compact', _id(), sessionId: _sessionId);
    return ((result['payload'] as Map?)?['content'] ?? '').toString();
  }

  static Future<void> recreate() async { _sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}'; }
  static agent_types.ConversationStats? getConversationStats() => null;
  static List<Map<String, dynamic>> getAvailableTools() => const [];
  static String _id() => 'req-${DateTime.now().microsecondsSinceEpoch}';
  static void answerQuestion(String questionId, Object answers) => _client.send('user.answer', _id(), {'questionId': questionId, 'answers': answers}, _sessionId);
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
      'systemPrompt': settings.agentSystemPrompt,
      'usageRules': settings.agentUsageRules,
    };
  }
}

sealed class AgentStreamEvent {}
class AgentTokenEvent extends AgentStreamEvent { AgentTokenEvent(this.text); final String text; }
class AgentRoundEvent extends AgentStreamEvent { AgentRoundEvent(this.round); final int round; }
class AgentQuestionEvent extends AgentStreamEvent { AgentQuestionEvent(this.questionId, this.questions); final String questionId; final List<AgentQuestion> questions; }
class AgentToolEvent extends AgentStreamEvent { AgentToolEvent(this.id, this.name, this.running, {this.error = false, this.details, this.changes}); final String id; final String name; final bool running; final bool error; final dynamic details; final dynamic changes; }
class AgentException implements Exception { AgentException(this.message); final String message; @override String toString() => message; }
