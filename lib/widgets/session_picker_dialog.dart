import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chat_storage_service.dart';
import '../theme/chat_theme.dart';

/// 历史会话选择弹窗（menu 窗口内模态）：列出 ChatStorageService 的会话，
/// 点击选中后经 Navigator.pop 返回该会话。
///
/// 弹窗挂在 navigator 层（在 HomeScreen 的 [ChatThemeScope] 之外），
/// 故宿主调用时必须用 `ChatThemeScope(data: _themeData, child: ...)` 包一层，
/// 本组件内部才能经 [ChatTheme.of] 取到当前主题。
class SessionPickerDialog extends StatefulWidget {
  const SessionPickerDialog({super.key, required this.conversations});

  final List<ChatConversation> conversations;

  @override
  State<SessionPickerDialog> createState() => _SessionPickerDialogState();
}

class _SessionPickerDialogState extends State<SessionPickerDialog> {
  static const _fontFamily = ChatTheme.fontFamily;
  // 预留标题、副标题及上下内边距，避免固定行高造成 RenderFlex 溢出。
  static const _itemExtent = 60.0;

  int? _hoverIndex;
  late int _selectedIndex;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.conversations.isEmpty ? -1 : 0;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectIndex(int index) {
    setState(() => _selectedIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final centeredOffset = index * _itemExtent -
          (position.viewportDimension - _itemExtent) / 2;
      final targetOffset = centeredOffset.clamp(
        0.0,
        position.maxScrollExtent,
      );
      if ((position.pixels - targetOffset).abs() > 0.5) {
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.conversations.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectIndex((_selectedIndex + 1) % widget.conversations.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectIndex((_selectedIndex - 1 + widget.conversations.length) %
          widget.conversations.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      Navigator.pop(context, widget.conversations[_selectedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 420),
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
            _buildHeader(theme),
            Container(height: 1, color: theme.lineSoft),
            Flexible(child: _buildList(theme)),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildHeader(ChatThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Text(
            '历史会话',
            style: TextStyle(
              color: theme.ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: _fontFamily,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.conversations.length}',
            style: TextStyle(
              color: theme.ink3,
              fontSize: 13,
              fontFamily: _fontFamily,
            ),
          ),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close,
                    size: 16, color: theme.ink3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ChatThemeData theme) {
    if (widget.conversations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            '暂无历史会话',
            style: TextStyle(
              color: theme.ink3,
              fontSize: 14,
              fontFamily: _fontFamily,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      itemExtent: _itemExtent,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: widget.conversations.length,
      itemBuilder: (_, index) => _buildItem(index, theme),
    );
  }

  Widget _buildItem(int index, ChatThemeData theme) {
    final conv = widget.conversations[index];
    final hovered = _hoverIndex == index;
    final selected = _selectedIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() {
        _hoverIndex = index;
        _selectedIndex = index;
      }),
      onExit: (_) => setState(() => _hoverIndex = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context, conv),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: hovered || selected ? theme.hover : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conv.title.isEmpty ? '未命名会话' : conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? theme.ink : theme.ink2,
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        fontFamily: _fontFamily,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_formatTime(conv.updatedAt)} · ${conv.messages.length} 条消息',
                      style: TextStyle(
                        color: theme.ink3,
                        fontSize: 12,
                        fontFamily: _fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${two(t.hour)}:${two(t.minute)}';
    }
    if (t.year == now.year) return '${t.month}-${two(t.day)}';
    return '${t.year}-${t.month}-${two(t.day)}';
  }
}
