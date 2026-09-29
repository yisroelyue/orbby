import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/todo_service.dart';
import 'note_theme.dart';

/// 笔记视图：折叠单行 / 点击展开编辑，重要笔记（旗帜图标 + 折叠行琥珀点）
/// 排在前面。数据与编辑器状态自管，统计经 onStats 回调给外壳头部副标题。
class NotesView extends StatefulWidget {
  const NotesView({super.key, required this.onStats});

  final void Function(int total, int important) onStats;

  @override
  State<NotesView> createState() => NotesViewState();
}

class NotesViewState extends State<NotesView> {
  List<TodoItem> _items = const [];
  bool _loading = true;
  String? _expandedId;
  TextEditingController? _editorController;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _editorController?.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await TodoService.loadAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    widget.onStats(
      items.length,
      items.where((item) => item.important).length,
    );
  }

  /// 外壳底部「新建笔记」入口。
  Future<void> createNote() async {
    await _saveEditor();
    final item = await TodoService.add('');
    await _loadItems();
    if (mounted) _expandItem(_items.firstWhere((value) => value.id == item.id));
  }

  Future<void> _toggleItem(TodoItem item) async {
    await _saveEditor();
    await TodoService.toggle(item.id);
    await _loadItems();
  }

  Future<void> _removeItem(TodoItem item) async {
    await _saveEditor();
    await TodoService.remove(item.id);
    _closeEditor();
    await _loadItems();
  }

  Future<void> _markImportant(TodoItem item) async {
    await _saveEditor();
    await TodoService.markImportant(item.id);
    await _loadItems();
    if (mounted) {
      _expandItem(_items.firstWhere((value) => value.id == item.id));
    }
  }

  void _expandItem(TodoItem item) {
    if (_expandedId == item.id) return;
    _closeEditor();
    final controller = TextEditingController(text: item.title);
    controller.addListener(_scheduleSave);
    setState(() {
      _expandedId = item.id;
      _editorController = controller;
    });
  }

  void _closeEditor() {
    _saveTimer?.cancel();
    _editorController?.removeListener(_scheduleSave);
    _editorController?.dispose();
    _editorController = null;
    _expandedId = null;
  }

  Future<void> collapseEditor() async {
    if (_expandedId == null) return;
    await _saveEditor();
    if (!mounted) return;
    setState(_closeEditor);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveEditor);
  }

  Future<void> _saveEditor() async {
    _saveTimer?.cancel();
    final id = _expandedId;
    final controller = _editorController;
    if (id == null || controller == null) return;
    await TodoService.updateTitle(id, controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: NoteColors.ink3),
      );
    }
    if (_items.isEmpty) {
      // 空态需要显式给宽（滚动方向无界约束下虚线框会缩成文字宽）。
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            child: const DashedPlaceholder(text: '暂无笔记，点击下方「新建笔记」'),
          ),
        ),
      );
    }
    // 重要在前，组内保持存储顺序（新建在前）。
    final sorted = [..._items]..sort((a, b) {
        if (a.important != b.important) return a.important ? -1 : 1;
        return 0;
      });
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final item = sorted[index];
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 7),
          child: _expandedId == item.id
              ? _buildEditor(item)
              : _buildRow(item),
        );
      },
    );
  }

  Widget _noteIcon(TodoItem item, {double size = 24}) => SvgPicture.asset(
        item.important ? 'assets/svg/todo-i.svg' : 'assets/svg/todo.svg',
        width: size,
        height: size,
      );

  Widget _buildRow(TodoItem item) {
    return HoverBuilder(
      builder: (context, hover) => GestureDetector(
        onTap: () => _expandItem(item),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: noteCardDecoration(hover: hover),
          child: Row(
            children: [
              _noteIcon(item),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title.trim().isEmpty ? '空笔记' : item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    letterSpacing: .1,
                    height: 1.4,
                    decoration: item.completed ? TextDecoration.lineThrough : null,
                    decorationColor: NoteColors.ink3,
                    color: item.title.trim().isEmpty
                        ? NoteColors.ink3
                        : (item.completed ? NoteColors.ink3 : NoteColors.ink),
                  ),
                ),
              ),
              if (item.important) ...[
                const SizedBox(width: 6),
                const Tooltip(
                  message: '重要',
                  child: _ImportantDot(),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 16, color: NoteColors.chevron),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(TodoItem item) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: noteEditorDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _noteIcon(item),
          TextField(
            controller: _editorController,
            autofocus: true,
            maxLines: null,
            minLines: 3,
            style: const TextStyle(
              fontSize: 13,
              height: 1.75,
              letterSpacing: .1,
              color: NoteColors.body,
            ),
            decoration: const InputDecoration(
              hintText: '输入笔记…',
              hintStyle: TextStyle(color: NoteColors.ink3, fontSize: 13),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(22, 7, 3, 0),
            ),
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.only(top: 10, right: 3),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: NoteColors.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconAction(
                  icon: item.completed ? Icons.undo_rounded : Icons.check_circle_outlined,
                  tooltip: item.completed ? '撤销完成' : '完成',
                  onTap: () => _toggleItem(item),
                ),
                const SizedBox(width: 6),
                IconAction(
                  icon: item.important ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                  tooltip: item.important ? '取消重要' : '标记重要',
                  active: item.important,
                  onTap: () => _markImportant(item),
                ),
                const SizedBox(width: 6),
                IconAction(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '删除',
                  danger: true,
                  onTap: () => _removeItem(item),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 折叠行右上角的琥珀小圆点：标记重要笔记。
class _ImportantDot extends StatelessWidget {
  const _ImportantDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: NoteColors.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x33FFC145), blurRadius: 3),
        ],
      ),
    );
  }
}
