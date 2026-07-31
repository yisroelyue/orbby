import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../screens/home_screen.dart';
import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import '../services/todo_service.dart';
import 'base_panel.dart';

class TodoPanel extends BasePanel {
  const TodoPanel({super.key});

  @override
  String get panelName => 'todo';

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends BasePanelState<TodoPanel> {
  List<TodoItem> _normalTodos = [];
  List<TodoItem> _importantTodos = [];
  bool _loading = true;
  bool _addHovered = false;
  bool _titleHovered = false;
  String? _hoveredId;

  static const Color _notebookBg = Color(0xFFFFF8DC); // 浅黄色背景
  static const Color _darkText = Color(0xFF333333); // 深色文字（用于浅色背景）

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);
    if (!PanelCache.has('todo_items')) {
      setState(() => _loading = true);
      PanelDataService.refreshTodo();
    }
  }

  @override
  void dispose() {
    PanelCache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<List<TodoItem>>('todo_items');
    if (cached != null && mounted) {
      final uncompleted = cached.where((t) => !t.completed).toList();
      setState(() {
        _normalTodos = uncompleted.where((t) => !t.important).toList();
        _importantTodos = uncompleted.where((t) => t.important).toList();
        _loading = false;
      });
    }
  }

  void _openItemPopup(TodoItem item) {
    HomeScreen.menuChannel.invokeMethod('open_todo_item_popup', {
      'id': item.id,
      'title': item.title,
      'important': item.important,
    });
  }

  void _openAddPopup() {
    HomeScreen.menuChannel.invokeMethod('open_todo_item_popup', {
      'id': '',
      'title': '',
    });
  }

  Future<void> _toggleComplete(TodoItem item) async {
    await TodoService.toggle(item.id);
    PanelDataService.refreshTodo();
  }

  void _openAllTodos() {
    HomeScreen.menuChannel.invokeMethod('open_todo_editor', {
      'id': '',
      'title': '',
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    // 实际内容在 build() 中渲染（需要 MouseRegion 包裹）
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(panelBorderRadius),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _notebookBg,
          borderRadius: BorderRadius.circular(panelBorderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            GestureDetector(
              onTap: _openAllTodos,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _titleHovered = true),
                onExit: (_) => setState(() => _titleHovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: _titleHovered
                        ? _darkText.withValues(alpha: 0.06)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      SvgPicture.asset('assets/svg/笔记.svg', width: 22, height: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '我的笔记',
                          style: TextStyle(
                            color: _darkText,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // 添加按钮
                      GestureDetector(
                        onTap: _openAddPopup,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _addHovered = true),
                          onExit: (_) => setState(() => _addHovered = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _addHovered ? elementBg : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.add,
                              color: _addHovered ? _darkText : _darkText.withValues(alpha: 0.5),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tertiaryText,
                    ),
                  ),
                ),
              )
            else
              _buildTodoList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoList() {
    final totalCount = _normalTodos.length + _importantTodos.length;
    if (totalCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            '暂无笔记，添加一个吧',
            style: TextStyle(color: _darkText, fontSize: 13),
          ),
        ),
      );
    }
    return SizedBox(
      height: 200,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          shrinkWrap: true,
          children: [
            ..._buildTodoListWithDividers(_normalTodos),
            if (_importantTodos.isNotEmpty && _normalTodos.isNotEmpty)
              _buildNotebookLine(),
            ..._buildTodoListWithDividers(_importantTodos),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTodoListWithDividers(List<TodoItem> items) {
    final widgets = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        widgets.add(_buildNotebookLine());
      }
      widgets.add(_buildTodoItem(items[i]));
    }
    return widgets;
  }

  Widget _buildNotebookLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          color: const Color(0xFFEDE6D0),
        ),
      ),
    );
  }

  Widget _buildTodoItem(TodoItem item) {
    final isHovered = _hoveredId == item.id;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredId = item.id),
      onExit: (_) => setState(() => _hoveredId = null),
      child: GestureDetector(
        onTap: () => _openItemPopup(item),
        child: Container(
          key: ValueKey(item.id),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isHovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (item.important)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.access_time_filled_rounded,
                    size: 14,
                    color: const Color(0xFF4C4C4C),
                  ),
                )
              else
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isHovered ? _darkText : _darkText.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(color: _darkText, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!item.important)
                GestureDetector(
                  onTap: () => _toggleComplete(item),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: isHovered ? Colors.greenAccent : _darkText.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
