import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import '../services/todo_service.dart';
import 'base_panel.dart';

class TodoPanel extends BasePanel {
  const TodoPanel({super.key});

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends BasePanelState<TodoPanel> {
  List<TodoItem> _normalTodos = [];
  List<TodoItem> _importantTodos = [];
  bool _panelEnabled = true;
  bool _loading = true;
  bool _addHovered = false;
  String? _hoveredId;
  bool _panelHovered = false;

  @override
  String get panelTitle => '我的笔记';

  @override
  PanelIcon get panelIcon => const PanelIcon.svg('assets/svg/笔记.svg');

  @override
  VoidCallback? get onHeaderTap => _openAllTodos;

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  bool get panelHovered => _panelHovered;

  @override
  void initState() {
    super.initState();
    _fetch(firstLoad: true);
    MenuScreen.todoRefreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    MenuScreen.todoRefreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _fetch();
  }

  Future<void> _fetch({bool firstLoad = false}) async {
    if (firstLoad) {
      setState(() => _loading = true);
    }
    final settings = await SettingsService.load();
    _panelEnabled = settings.showTodoPanel;
    if (!_panelEnabled) {
      if (!mounted) return;
      if (firstLoad) setState(() => _loading = false);
      return;
    }
    final todos = await TodoService.loadAll();
    if (!mounted) return;
    setState(() {
      final uncompleted = todos.where((t) => !t.completed).toList();
      _normalTodos = uncompleted.where((t) => !t.important).toList();
      _importantTodos = uncompleted.where((t) => t.important).toList();
      _loading = false;
    });
  }

  void _openItemPopup(TodoItem item) {
    MenuScreen.menuChannel.invokeMethod('open_todo_item_popup', {
      'id': item.id,
      'title': item.title,
      'important': item.important,
    });
  }

  void _openAddPopup() {
    MenuScreen.menuChannel.invokeMethod('open_todo_item_popup', {
      'id': '',
      'title': '',
    });
  }

  Future<void> _toggleComplete(TodoItem item) async {
    await TodoService.toggle(item.id);
    _fetch();
    MenuScreen.todoRefreshNotifier.value++;
  }

  void _openAllTodos() {
    MenuScreen.menuChannel.invokeMethod('open_todo_editor', {
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
  List<Widget> buildHeaderActions() {
    return [
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
              color: _addHovered ? primaryText : mutedText,
              size: 20,
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_panelEnabled && !_loading) {
      return const SizedBox.shrink();
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _panelHovered = true),
      onExit: (_) => setState(() => _panelHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BasePanelState.panelBorderRadius),
        child: Container(
          padding: const EdgeInsets.all(16),
          color: panelBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              buildHeader(),
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
            style: TextStyle(color: primaryText, fontSize: 13),
          ),
        ),
      );
    }
    final showAll = _panelHovered;
    final normalVisible = showAll
        ? _normalTodos.length
        : (_normalTodos.length > 3 ? 3 : _normalTodos.length);
    final importantVisible = showAll ? _importantTodos.length : 0;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(
            normalVisible,
            (i) => _buildTodoItem(_normalTodos[i]),
          ),
          if (importantVisible > 0 && normalVisible > 0)
            _buildDivider(),
          ...List.generate(
            importantVisible,
            (i) => _buildTodoItem(_importantTodos[i]),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        height: 1,
        color: elementBg,
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
                    Icons.star_rounded,
                    size: 14,
                    color: isHovered
                        ? Colors.amberAccent
                        : Colors.amberAccent.withValues(alpha: 0.7),
                  ),
                )
              else
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isHovered ? primaryText : mutedText,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(color: primaryText, fontSize: 14),
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
                      color: isHovered ? Colors.greenAccent : mutedText,
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
