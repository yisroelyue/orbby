import 'dart:math';

import 'package:flutter/material.dart';

import '../config/constants.dart';
import 'pet_ball.dart';

/// 雅黑风格悬浮球 —— 灰色圆底 + 中心白色圆环呼吸动画
class PetBallRound extends PetBall {
  const PetBallRound({super.key});

  @override
  Widget buildContent(BuildContext context) {
    return const _PulsingRing();
  }
}

class _PulsingRing extends StatefulWidget {
  const _PulsingRing();

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with TickerProviderStateMixin {
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
        final t = sin(_controller.value * pi);
        final ballRadius = PetConfig.ballSize / 2;
        // 白圈半径在 30% ~ 75% 之间变化
        final radius = ballRadius * (0.40 + 0.25 * t);

        return Container(
          decoration: BoxDecoration(
            color: Color(0xd0434343),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
