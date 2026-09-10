import 'dart:async';
import '../agent/agent_ws_client.dart';
import '../agent/types.dart' as agent_types;
import '../config/settings.dart';
import '../config/platform.dart';

class AgentService {
  AgentService._();
  static final AgentWsClient _client = AgentWsClient();
  static String _sessionId = 'default';

  static void setSystemPrompt(String? prompt) {}

  /// Compatibility hook retained for callers from the pre-WebSocket Agent.
  /// Logging is owned by the Node runtime now and is sent with future runtime
  /// configuration messages rather than mutating a Dart Agent instance.
  static Future<void> syncLogSettings() async {}

  static Future<String> chat(String text, {String mode = 'accept', List<Map<String, String>> history = const []}) async {
    final id = _id();
    final result = await _client.request('chat.start', id, sessionId: _sessionId, payload: {'message': text, 'mode': mode, 'history': history, 'llm': await _llmPayload()});
    return ((result['payload'] as Map?)?['content'] ?? '').toString();
  }

  static Stream<AgentStreamEvent> chatStream(String text, {String mode = 'accept', List<Map<String, String>> history = const []}) async* {
    final id = _id();
    await _client.connect();
    final subscription = _client.events.where((e) => e['requestId'] == id).listen(null);
    final queue = StreamController<AgentStreamEvent>();
    subscription.onData((event) {
      switch (event['type']) {
        case 'agent.token': queue.add(AgentTokenEvent(((event['payload'] as Map)['text'] ?? '').toString()));
        case 'agent.round': queue.add(AgentRoundEvent((event['payload'] as Map)['round'] as int));
        case 'agent.done': queue.close();
        case 'agent.error': queue.addError(Exception((event['error'] as Map)['message'])); queue.close();
      }
    });
    _client.send('chat.start', id, {'message': text, 'mode': mode, 'history': history, 'llm': await _llmPayload()}, _sessionId);
    try { yield* queue.stream; } finally { await subscription.cancel(); if (!queue.isClosed) await queue.close(); }
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
  static Future<Map<String, dynamic>> _llmPayload() async {
    final settings = await SettingsService.load();
    final url = settings.chatUrl.isEmpty ? PlatformConfig.defaultChatUrl(settings.platform) : settings.chatUrl.trim();
    final model = settings.model.isEmpty ? PlatformConfig.defaultChatModel(settings.platform) : settings.model;
    return {'url': url, 'apiKey': settings.apiKey, 'model': model};
  }
}

sealed class AgentStreamEvent {}
class AgentTokenEvent extends AgentStreamEvent { AgentTokenEvent(this.text); final String text; }
class AgentRoundEvent extends AgentStreamEvent { AgentRoundEvent(this.round); final int round; }
class AgentException implements Exception { AgentException(this.message); final String message; @override String toString() => message; }
