import 'package:flutter/material.dart';

import '../services/chat_command.dart';

/// 输入框上方的 '/' 命令提示列表（终端风格：左列命令名，右列说明）。
///
/// 纯展示组件：可见性、过滤结果与键盘选中项均来自 [CommandPaletteController]，
/// 本组件只负责渲染与点击；确认动作通过 [onConfirm] 交回宿主处理。
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
  /// 与聊天区统一的终端字体
  static const _fontFamily = 'Sarasa Mono SC';

  static const _rowHeight = 36.0;
  static const _maxVisibleRows = 6;
  static const _nameWidth = 132.0;

  static const _bg = Color(0xFF1E1E1E);
  static const _selectedBg = Color(0x24FFFFFF);
  static const _hoverBg = Color(0x12FFFFFF);
  static const _nameText = Color(0xFFEAEAEA);
  static const _descText = Color(0x73FFFFFF);

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

    final rows = controller.filtered;
    return Container(
      // 不可见时是 shrink 的空盒，间距随面板一起出现/消失
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(maxHeight: _rowHeight * _maxVisibleRows + 8),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        itemExtent: _rowHeight,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: rows.length,
        itemBuilder: (_, index) =>
            _buildRow(rows[index], index, index == controller.selectedIndex),
      ),
    );
  }

  Widget _buildRow(ChatCommand command, int index, bool selected) {
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
          color: selected
              ? _selectedBg
              : hovered
                  ? _hoverBg
                  : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: _nameWidth,
                child: Text(
                  '/${command.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _nameText,
                    fontSize: 13,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  command.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _descText,
                    fontSize: 12,
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
}
