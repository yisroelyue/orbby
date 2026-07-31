import 'dart:async';

import 'package:flutter/material.dart';

/// 全平台通用的居中 Toast 组件
class AppToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  /// 显示居中 Toast
  static void show(
    BuildContext context, {
    required String message,
    IconData icon = Icons.check_circle_rounded,
    Color iconColor = const Color(0xFF66BB6A),
    Duration duration = const Duration(seconds: 2),
  }) {
    _dismiss();

    _entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        icon: icon,
        iconColor: iconColor,
      ),
    );

    Overlay.of(context).insert(_entry!);

    _timer = Timer(duration, _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.icon,
    required this.iconColor,
  });

  final String message;
  final IconData icon;
  final Color iconColor;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xE62A2D3E),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: widget.iconColor, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
