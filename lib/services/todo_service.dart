import 'dart:convert';
import 'dart:io';

class TodoItem {
  TodoItem({
    required this.id,
    required this.title,
    this.completed = false,
    this.important = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  bool completed;
  bool important;
  final DateTime createdAt;

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completed'] as bool? ?? false,
      important: json['important'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
        'important': important,
        'createdAt': createdAt.toIso8601String(),
      };
}

class TodoService {
  TodoService._();

  static Future<File> _file() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/orbby_todos.json');
  }

  static Future<List<TodoItem>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString());
      final list = json as List<dynamic>;
      return list
          .map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<TodoItem> todos) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(todos.map((t) => t.toJson()).toList()),
    );
  }

  static Future<TodoItem> add(String title, {bool completed = false}) async {
    final todos = await loadAll();
    final item = TodoItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      completed: completed,
    );
    todos.insert(0, item);
    await saveAll(todos);
    return item;
  }

  static Future<void> toggle(String id) async {
    final todos = await loadAll();
    final idx = todos.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    todos[idx].completed = !todos[idx].completed;
    await saveAll(todos);
  }

  static Future<void> updateTitle(String id, String title) async {
    final todos = await loadAll();
    final idx = todos.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    todos[idx].title = title;
    await saveAll(todos);
  }

  static Future<void> remove(String id) async {
    final todos = await loadAll();
    todos.removeWhere((t) => t.id == id);
    await saveAll(todos);
  }

  static Future<void> markImportant(String id) async {
    final todos = await loadAll();
    final idx = todos.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    todos[idx].important = !todos[idx].important;
    await saveAll(todos);
  }
}
