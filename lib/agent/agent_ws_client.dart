import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AgentWsClient {
  WebSocket? _socket;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> connect() async {
    if (_socket != null) return;
    final url = Platform.environment['ORBBY_AGENT_URL'] ?? 'ws://127.0.0.1:43127';
    _socket = await WebSocket.connect(url);
    _socket!.listen((data) => _events.add(jsonDecode(data as String) as Map<String, dynamic>), onDone: () { _socket = null; if (!_events.isClosed) _events.addError(const AgentConnectionException('Agent 服务连接已断开')); }, onError: (Object e, StackTrace s) { if (!_events.isClosed) _events.addError(e, s); });
    send('hello', 'hello-${DateTime.now().microsecondsSinceEpoch}', {'protocolVersion': 1});
  }

  void send(String type, String requestId, [Map<String, dynamic> payload = const {}, String? sessionId]) {
    _socket?.add(jsonEncode({'type': type, 'requestId': requestId, if (sessionId != null) 'sessionId': sessionId, 'payload': payload}));
  }

  Future<Map<String, dynamic>> request(String type, String requestId, {String? sessionId, Map<String, dynamic> payload = const {}}) async {
    await connect();
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription<Map<String, dynamic>> subscription;
    subscription = events.listen((event) { if (event['requestId'] == requestId && (event['type'] == 'agent.done' || event['type'] == 'session.stats' || event['type'] == 'tools.list' || event['type'] == 'agent.error') && !completer.isCompleted) completer.complete(event); }, onError: (Object error, StackTrace stack) { if (!completer.isCompleted) completer.completeError(error, stack); }, onDone: () { if (!completer.isCompleted) completer.completeError(const AgentConnectionException('Agent 服务连接已断开')); });
    send(type, requestId, payload, sessionId);
    final result = await completer.future.timeout(const Duration(minutes: 5), onTimeout: () => throw TimeoutException('Agent request timed out'));
    await subscription.cancel();
    if (result['type'] == 'agent.error') throw Exception((result['error'] as Map)['message']);
    return result;
  }

  Future<void> close() async { await _socket?.close(); _socket = null; await _events.close(); }
}

class AgentConnectionException implements Exception { const AgentConnectionException(this.message); final String message; @override String toString() => message; }
