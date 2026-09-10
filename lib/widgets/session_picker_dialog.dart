import 'package:flutter/material.dart';

import '../services/chat_storage_service.dart';

/// 历史会话选择弹窗（menu 窗口内模态）：列出 ChatStorageService 的会话，
/// 点击选中后经 Navigator.pop 返回该会话。
class SessionPickerDialog extends StatefulWidget {
  const SessionPickerDialog({super.key, required this.conversations});

  final List<ChatConversation> conversations;

  @override
  State<SessionPickerDialog> createState() => _SessionPickerDialogState();
}

class _SessionPickerDialogState extends State<SessionPickerDialog> {
  static const _fontFamily = 'Sarasa Mono SC';

  static const _bg = Color(0xFF1E1E1E);
  static const _border = Color(0x1AFFFFFF);
  static const _divider = Color(0x14FFFFFF);
  static const _hoverBg = Color(0x12FFFFFF);
  static const _titleText = Color(0xFFEAEAEA);
  static const _subText = Color(0x73FFFFFF);

  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Container(height: 1, color: _divider),
            Flexible(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Text(
            '历史会话',
            style: TextStyle(
              color: _titleText,
              fontSize: 14,
              fontFamily: _fontFamily,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.conversations.length}',
            style: TextStyle(
              color: _subText,
              fontSize: 12,
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
                    size: 16, color: _subText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (widget.conversations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            '暂无历史会话',
            style: TextStyle(
              color: _subText,
              fontSize: 13,
              fontFamily: _fontFamily,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: widget.conversations.length,
      itemBuilder: (_, index) => _buildItem(index),
    );
  }

  Widget _buildItem(int index) {
    final conv = widget.conversations[index];
    final hovered = _hoverIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) => setState(() => _hoverIndex = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context, conv),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: hovered ? _hoverBg : Colors.transparent,
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
                        color: _titleText,
                        fontSize: 13,
                        fontFamily: _fontFamily,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_formatTime(conv.updatedAt)} · ${conv.messages.length} 条消息',
                      style: TextStyle(
                        color: _subText,
                        fontSize: 11,
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
