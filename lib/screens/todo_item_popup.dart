import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isControlPressed) {
        _insertNewline();
      } else {
        _save();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _insertNewline() {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start;
    final end = selection.end;
    _controller.text = text.substring(0, start) + '\n' + text.substring(end);
    _controller.selection = TextSelection.collapsed(offset: start + 1);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Microsoft YaHei',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B6EF5),
          brightness: Brightness.light,
        ),
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5B6EF5).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _isCreate ? Icons.add_rounded : Icons.edit_rounded,
                      color: const Color(0xFF5B6EF5),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isCreate ? '添加笔记' : '编辑笔记',
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!_isCreate && _important) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.star_rounded,
                      color: Colors.amber.shade600,
                      size: 18,
                    ),
                  ],
                  const Spacer(),
                  _buildIconBtn(
                    icon: Icons.close_rounded,
                    onTap: _cancel,
                    color: Colors.black,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Text field
              Expanded(
                child: Focus(
                  onKeyEvent: _handleKeyEvent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        // 横格线背景
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _NotepadLinesPainter(
                              lineColor: const Color(0xFFE8E8E8),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                              ),
                              topPadding: 12,
                            ),
                          ),
                        ),
                        // 输入框
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 14,
                            height: 1.5,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.transparent,
                            hintText: '输入笔记内容...',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Buttons
              Row(
                children: [
                  if (!_isCreate) ...[
                    _buildBtn(
                      _important ? '取消标记' : '标记重要',
                      _markImportant,
                      icon: Icons.access_time_filled_rounded,
                    ),
                    const SizedBox(width: 8),
                    _buildBtn(
                      '删除',
                      _delete,
                      icon: Icons.delete_outline_rounded,
                    ),
                  ],
                  const Spacer(),
                  _buildBtn(
                    '保存',
                    _save,
                    icon: Icons.check_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _buildBtn(
    String label,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return SizedBox(
      height: 34,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF5B6EF5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        icon: icon != null ? Icon(icon, size: 16) : const SizedBox.shrink(),
        label: Text(label),
      ),
    );
  }
}

// 笔记本横格线画笔
class _NotepadLinesPainter extends CustomPainter {
  final Color lineColor;
  final TextStyle textStyle;
  final double topPadding;

  _NotepadLinesPainter({
    required this.lineColor,
    required this.textStyle,
    required this.topPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    final lineHeight = (textStyle.fontSize ?? 14) * (textStyle.height ?? 1.5);
    double y = topPadding + lineHeight;
    while (y < size.height) {
      canvas.drawLine(
        Offset(12, y),
        Offset(size.width - 12, y),
        paint,
      );
      y += lineHeight;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
