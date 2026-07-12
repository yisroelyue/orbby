import 'dart:math';

import 'package:flutter/material.dart';

import '../config/constants.dart';
import 'pet_ball.dart';

/// 彩球风格悬浮球 —— 8 个彩色圆点围成的圆球，带波浪脉动动画
class PetBallColorful extends PetBall {
  const PetBallColorful({super.key});

  @override
  Widget buildContent(BuildContext context) {
    return const _ColorfulDots();
  }
}

class _ColorfulDots extends StatefulWidget {
  const _ColorfulDots();

  @override
  State<_ColorfulDots> createState() => _ColorfulDotsState();
}

class _ColorfulDotsState extends State<_ColorfulDots>
    with TickerProviderStateMixin {
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

  static double get _dotRadius => PetConfig.ballSize * 0.1;
  static double get _circleRadius => PetConfig.ballSize / 2 - _dotRadius;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
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
          child: SizedBox(
            width: _circleRadius * 2 + _dotRadius * 2,
            height: _circleRadius * 2 + _dotRadius * 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(_dotCount, (i) {
                final angle = (i / _dotCount) * 2 * pi - pi / 2;
                final delay = i / _dotCount;
                final phase = (_controller.value + delay) % 1.0;
                final scale = 0.35 + 0.65 * sin(phase * pi);

                final cx = _circleRadius + _dotRadius;
                final cy = _circleRadius + _dotRadius;
                final dx = cx + _circleRadius * cos(angle);
                final dy = cy + _circleRadius * sin(angle);

                return Positioned(
                  left: dx - _dotRadius,
                  top: dy - _dotRadius,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: _dotRadius * 2,
                      height: _dotRadius * 2,
                      decoration: BoxDecoration(
                        color: _dotColors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
