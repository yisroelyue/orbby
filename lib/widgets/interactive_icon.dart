import 'package:flutter/material.dart';

/// 带 hover 背景 + 按压缩放的交互图标按钮
class InteractiveIcon extends StatefulWidget {
  const InteractiveIcon({
    super.key,
    required this.onTap,
    required this.child,
    this.size = 32,
  });

  final VoidCallback onTap;
  final Widget child;
  final double size;

  @override
  State<InteractiveIcon> createState() => _InteractiveIconState();
}

class _InteractiveIconState extends State<InteractiveIcon> {
  bool _isHovering = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.82 : 1.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() {
        _isHovering = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _isHovering
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(widget.size / 2),
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}
