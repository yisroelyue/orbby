import 'dart:convert';
import 'dart:io';

class ChatConversation {
  ChatConversation({
    required this.id,
    required this.title,
    this.model = '',
    this.mode = 'accept',
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Map<String, String>>? messages,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  final String id;
  String title;
  String model;
  String mode;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<Map<String, String>> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'model': model,
        'mode': mode,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages,
      };

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      model: json['model'] as String? ?? '',
      mode: json['mode'] as String? ?? 'accept',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(e as Map))
              .toList() ??
          [],
    );
  }
}

class ChatStorageService {
  ChatStorageService._();

  static Future<String> get _taskDir async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby/task');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<List<ChatConversation>> loadAll() async {
    final dirPath = await _taskDir;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final conversations = <ChatConversation>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final id = entity.path.split(Platform.pathSeparator).last;
        final jsonFile = File('${entity.path}/$id.json');
        if (await jsonFile.exists()) {
          try {
            final raw = await jsonFile.readAsString();
            final json = jsonDecode(raw) as Map<String, dynamic>;
            conversations.add(ChatConversation.fromJson(json));
          } catch (_) {
            // 跳过损坏的文件
          }
        }
      }
    }

    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  static Future<ChatConversation?> load(String id) async {
    final dirPath = await _taskDir;
    final jsonFile = File('$dirPath/$id/$id.json');
    if (!await jsonFile.exists()) return null;
    try {
      final raw = await jsonFile.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ChatConversation.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(ChatConversation conv) async {
    final dirPath = await _taskDir;
    final convDir = Directory('$dirPath/${conv.id}');
    if (!await convDir.exists()) {
      await convDir.create(recursive: true);
    }
    final jsonFile = File('${convDir.path}/${conv.id}.json');
    conv.updatedAt = DateTime.now();
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(conv.toJson()),
    );
  }

  static Future<void> delete(String id) async {
    final dirPath = await _taskDir;
    final convDir = Directory('$dirPath/$id');
    if (await convDir.exists()) {
      await convDir.delete(recursive: true);
    }
  }

  static Future<void> deleteAll() async {
    final dirPath = await _taskDir;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
  }
}
