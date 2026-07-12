import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/todo_service.dart';
import '../widgets/interactive_icon.dart';

class TodoItemPopup extends StatefulWidget {
  const TodoItemPopup({super.key});

  static const popupChannel = WindowMethodChannel(
    'orbby_todo_item_popup_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<TodoItemPopup> createState() => _TodoItemPopupState();
}

class _TodoItemPopupState extends State<TodoItemPopup> {
  final _controller = TextEditingController();
  String _id = '';
  String _title = '';
  bool _important = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = await WindowController.fromCurrentEngine();
    // Set up handler for reuse
    c.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'set_data':
          final args = call.arguments as Map;
          _id = args['id'] as String? ?? '';
          _title = args['title'] as String? ?? '';
          _important = args['important'] as bool? ?? false;
          _controller.text = _title;
          final w = (args['width'] as num?)?.toDouble() ?? 400;
          final h = (args['height'] as num?)?.toDouble() ?? 300;
          final l = (args['left'] as num?)?.toDouble() ?? 0;
          final t = (args['top'] as num?)?.toDouble() ?? 0;
          await windowManager.setMinimumSize(Size(w, h));
          await windowManager.setMaximumSize(Size(w, h));
          await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
          await windowManager.show();
          if (mounted) setState(() {});
          return;
        default:
          throw UnimplementedError('Not implemented: ${call.method}');
      }
    });

    // First load
    final args = _parseArgs(c.arguments);
    _id = args['id'] as String? ?? '';
    _title = args['title'] as String? ?? '';
    _important = args['important'] as bool? ?? false;
    _controller.text = _title;
    final w = (args['width'] as num?)?.toDouble() ?? 400;
    final h = (args['height'] as num?)?.toDouble() ?? 300;
    final l = (args['left'] as num?)?.toDouble() ?? 0;
    final t = (args['top'] as num?)?.toDouble() ?? 0;
    await windowManager.setMinimumSize(Size(w, h));
    await windowManager.setMaximumSize(Size(w, h));
    await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
    if (args['hidden'] != true) {
      await windowManager.show();
    }
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _parseArgs(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  bool get _isCreate => _id.isEmpty;

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_isCreate) {
      await TodoService.add(text);
    } else {
      await TodoService.updateTitle(_id, text);
    }
    await windowManager.hide();
    TodoItemPopup.popupChannel.invokeMethod('todo_item_saved');
  }

  Future<void> _delete() async {
    if (_id.isNotEmpty) {
      await TodoService.remove(_id);
    }
    await windowManager.hide();
    TodoItemPopup.popupChannel.invokeMethod('todo_item_saved');
  }

  Future<void> _markImportant() async {
    if (_id.isEmpty) return;
    await TodoService.markImportant(_id);
    setState(() => _important = !_important);
    TodoItemPopup.popupChannel.invokeMethod('todo_item_marked');
  }

  Future<void> _cancel() async {
    await windowManager.hide();
    TodoItemPopup.popupChannel.invokeMethod('todo_item_dismissed');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSansSC'),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!_isCreate && _important)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star_rounded,
                        color: Colors.amberAccent.withValues(alpha: 0.85),
                        size: 18,
                      ),
                    ),
                  Icon(
                    _isCreate ? Icons.add_circle_outline : Icons.edit_note_rounded,
                    color: Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isCreate ? '添加笔记' : '编辑笔记',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InteractiveIcon(
                    size: 28,
                    onTap: _cancel,
                    child: const Icon(Icons.close,
                        color: Colors.white38, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (!_isCreate) ...[
                    _buildBtn(
                      _important ? '取消标记' : '标记',
                      _markImportant,
                      accent: true,
                    ),
                    const SizedBox(width: 6),
                    _buildBtn('删除', _delete, destructive: true),
                  ],
                  const Spacer(),
                  _buildBtn('保存', _save, primary: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBtn(
    String label,
    VoidCallback onTap, {
    bool primary = false,
    bool destructive = false,
    bool accent = false,
  }) {
    return SizedBox(
      height: 28,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: primary
              ? Colors.black87
              : destructive
                  ? Colors.white70
                  : accent
                      ? Colors.black87
                      : Colors.white,
          backgroundColor: primary
              ? Colors.greenAccent.withValues(alpha: 0.85)
              : destructive
                  ? Colors.redAccent.withValues(alpha: 0.35)
                  : accent
                      ? Colors.amberAccent.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text(label),
      ),
    );
  }
}
