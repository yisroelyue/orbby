import 'package:flutter/material.dart';

import '../services/chat_command.dart';
import '../theme/chat_theme.dart';

/// 输入框上方的 '/' 命令提示列表（左列命令名，右列说明）。
///
/// 纯展示组件：可见性、过滤结果与键盘选中项均来自 [CommandPaletteController]，
/// 本组件只负责渲染与点击；确认动作通过 [onConfirm] 交回宿主处理。
/// 视觉与提问卡片同源（参考稿 .pop）：raised 卡片 + 12px 圆角 + 浮层阴影。
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.controller,
    required this.onConfirm,
  });

  final CommandPaletteController controller;
  final ValueChanged<ChatCommand> onConfirm;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  /// 与聊天区统一（[ChatTheme.fontFamily]）
  static const _fontFamily = ChatTheme.fontFamily;

  static const _rowHeight = 34.0;
  static const _headerHeight = 32.0;
  static const _maxVisibleRows = 6;
  static const _nameWidth = 126.0;

  final _scrollController = ScrollController();
  int? _hoverIndex;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant CommandPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    // 键盘移动选中项时保证可见
    final c = widget.controller;
    if (!c.visible || !_scrollController.hasClients) return;
    final target = (c.selectedIndex * _rowHeight).toDouble().clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
    if ((target - _scrollController.offset).abs() > 0.5) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.visible) return const SizedBox.shrink();

    final theme = ChatTheme.of(context);
    final rows = controller.filtered;
    return Container(
      // 不可见时是 shrink 的空盒，间距随面板一起出现/消失
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(bottom: 8),
      constraints: BoxConstraints(
        maxHeight: _headerHeight + _rowHeight * _maxVisibleRows + 8,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.line),
        boxShadow: theme.popShadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _headerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '命令（${rows.length}）',
                  style: TextStyle(
                    color: theme.isDark ? Colors.white : theme.ink2,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              itemExtent: _rowHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: rows.length,
              itemBuilder: (_, index) => _buildRow(
                rows[index],
                index,
                index == controller.selectedIndex,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ChatCommand command, int index, bool selected) {
    final theme = ChatTheme.of(context);
    final hovered = _hoverIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) => setState(() => _hoverIndex = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onConfirm(command),
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected || hovered
                ? (theme.isDark ? theme.hover : const Color(0xFFF3F4F6))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _nameWidth,
                child: Row(
                  children: [
                    Text(
                      '/${command.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.isDark
                            ? Colors.white
                            : (selected ? theme.ink : theme.ink2),
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        fontFamily: _fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _iconForCommand(command.name),
                size: 16,
                color: selected ? theme.ink : theme.ink2,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  command.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.isDark ? Colors.white : theme.ink3,
                    fontSize: 13,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForCommand(String name) => switch (name) {
        'help' => Icons.help_outline,
        'session' => Icons.history,
        'new' => Icons.add_circle_outline,
        'close' || 'clear' || 'clear-session' => Icons.delete_outline,
        'compact' => Icons.compress,
        'status' => Icons.info_outline,
        'cd' => Icons.folder_open,
        'personality' => Icons.face_outlined,
        'rollback' => Icons.undo,
        'retry' => Icons.refresh,
        'copy' || 'copy-txt' => Icons.content_copy,
        'apps' => Icons.apps,
        'reload-skill' => Icons.auto_awesome,
        'sys_setting' || 'setting' => Icons.settings_outlined,
        'permission-off' || 'permission-all' || 'permission-read' || 'permission' => Icons.lock_outline,
        _ => Icons.terminal,
      };
}
