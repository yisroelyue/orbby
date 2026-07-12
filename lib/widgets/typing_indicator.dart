import 'dart:math';

import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with TickerProviderStateMixin {
  static const _dotCount = 8;
  static const _dotColors = [
    Color(0xFFFF6B6B), // coral
    Color(0xFFFF9F43), // orange
    Color(0xFFFFD93D), // gold
    Color(0xFF6BCB77), // green
    Color(0xFF54A0FF), // blue
    Color(0xFF5F27CD), // purple
    Color(0xFFFF6B9D), // pink
    Color(0xFF00D2D3), // teal
  ];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_dotCount, (i) {
              final delay = i / _dotCount;
              final t = (_controller.value - delay).clamp(0.0, 1.0);
              final scale = 0.3 + 0.7 * sin(t * pi);
              return Padding(
                padding: EdgeInsets.only(left: i > 0 ? 6 : 0),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _dotColors[i],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
