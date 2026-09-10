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
    _socket!.listen((data) => _events.add(jsonDecode(data as String) as Map<String, dynamic>), onDone: () => _socket = null, onError: (Object e) => _events.addError(e));
    send('hello', 'hello-${DateTime.now().microsecondsSinceEpoch}', {'protocolVersion': 1});
  }

  void send(String type, String requestId, [Map<String, dynamic> payload = const {}, String? sessionId]) {
    _socket?.add(jsonEncode({'type': type, 'requestId': requestId, if (sessionId != null) 'sessionId': sessionId, 'payload': payload}));
  }

  Future<Map<String, dynamic>> request(String type, String requestId, {String? sessionId, Map<String, dynamic> payload = const {}}) async {
    await connect();
    final future = events.firstWhere((e) => e['requestId'] == requestId && (e['type'] == 'agent.done' || e['type'] == 'session.stats' || e['type'] == 'tools.list' || e['type'] == 'agent.error'));
    send(type, requestId, payload, sessionId);
    final result = await future;
    if (result['type'] == 'agent.error') throw Exception((result['error'] as Map)['message']);
    return result;
  }

  Future<void> close() async { await _socket?.close(); _socket = null; await _events.close(); }
}
