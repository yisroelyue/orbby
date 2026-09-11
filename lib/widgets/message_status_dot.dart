import 'package:flutter/material.dart';

enum MessageStatus { user, processing, completed, terminated }

class MessageStatusDot extends StatefulWidget {
  const MessageStatusDot({super.key, required this.status});
  final MessageStatus status;

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
    final processing = widget.status == MessageStatus.processing;
    final color = switch (widget.status) {
      MessageStatus.user => const Color(0xFFF0A04B),
      MessageStatus.processing => const Color(0xFF9A9A9A),
      MessageStatus.completed => const Color(0xFF55C878),
      MessageStatus.terminated => const Color(0xFFE05252),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 7, right: 10),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Opacity(
          opacity: processing ? 0.3 + _controller.value * 0.7 : 1,
          child: child,
        ),
        child: Container(
          width: 6, height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
