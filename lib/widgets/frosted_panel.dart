import 'package:flutter/material.dart';

class FrostedPanel extends StatelessWidget {
  const FrostedPanel({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color),
      child: child,
    );
  }
}
