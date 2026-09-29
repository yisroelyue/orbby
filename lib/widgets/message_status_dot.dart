import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';

enum MessageStatus { user, processing, completed, terminated }

class MessageStatusDot extends StatefulWidget {
  const MessageStatusDot({
    super.key,
    required this.status,
    this.lineHeight = 24,
  });

  final MessageStatus status;

  /// 同排首行文字的**实际行高**（fontSize × height，单位 px）。
  /// 圆点据此垂直居中于首行——不要退回固定 top 魔数：魔数是按某一档字号
  /// 凑出来的，字号一改（如整体 +1px）圆点就会明显偏上，与正文对不齐。
  final double lineHeight;

  @override
  State<MessageStatusDot> createState() => _MessageStatusDotState();
}

class _MessageStatusDotState extends State<MessageStatusDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    final processing = widget.status == MessageStatus.processing;
    // 用户消息与思考中的圆点放大一档（9px），与完成/终止的静态小点（6px）区分
    final large = processing || widget.status == MessageStatus.user;
    final color = switch (widget.status) {
      MessageStatus.user => theme.userDot,
      MessageStatus.processing => theme.ink3,
      MessageStatus.completed => theme.done,
      MessageStatus.terminated => theme.term,
    };
    final size = large ? 9.0 : 6.0;
    // 圆点中心落在首行中心：行高与圆点直径之差取半（行高过小时退化为贴顶，
    // 避免 EdgeInsets 出现负值被 RenderPadding 断言拦下）
    final top = (widget.lineHeight - size) / 2;
    return Padding(
      padding: EdgeInsets.only(top: top > 0 ? top : 0, right: 10),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Opacity(
          opacity: processing ? 0.3 + _controller.value * 0.7 : 1,
          child: child,
        ),
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
