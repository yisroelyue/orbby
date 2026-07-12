import 'package:flutter/material.dart';

import '../config/constants.dart';

/// 悬浮球抽象基类，统一 50×50 尺寸约束
abstract class PetBall extends StatelessWidget {
  const PetBall({super.key});

  /// 子类实现具体的球体绘制
  Widget buildContent(BuildContext context);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: PetConfig.ballSize,
      height: PetConfig.ballSize,
      child: buildContent(context),
    );
  }
}
