import 'dart:convert';
import 'dart:io';

class ChatLogService {
  ChatLogService._();

  static Future<void> write(String conversationId, String type, Object? data) async {
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
      final dir = Directory('$home/.orbby/task/$conversationId');
      await dir.create(recursive: true);
      final isMessage = type == 'request' ||
          type == 'raw.response' ||
          type == 'llm.response';
      final file = File('${dir.path}/${isMessage ? 'messages' : 'events'}.log');
      await file.writeAsString(
        '${jsonEncode({'time': DateTime.now().toIso8601String(), 'type': type, 'data': data})}\n',
        mode: FileMode.append,
        encoding: utf8,
      );
    } catch (_) {}
  }
}
