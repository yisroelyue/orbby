import 'dart:async';

import 'package:flutter/material.dart';

/// 预加载的提示弹窗组件
/// 用于在 hover 或点击时显示功能描述
class TooltipPopup {
  static OverlayEntry? _overlayEntry;
  static bool _isVisible = false;
  static Timer? _showTimer;

  /// 预加载弹窗（在应用启动时调用）
  static void preload(BuildContext context) {
    // 预加载逻辑，可以在应用启动时调用
  }

  /// 显示提示弹窗（带延迟）
  static void show({
    required BuildContext context,
    required String title,
    required String description,
    required Offset position,
    bool isDark = true,
    Duration delay = const Duration(milliseconds: 400),
  }) {
    hide();

    _showTimer = Timer(delay, () {
      _overlayEntry = OverlayEntry(
        builder: (context) => _TooltipContent(
          title: title,
          description: description,
          position: position,
          isDark: isDark,
          onDismiss: hide,
        ),
      );

      Overlay.of(context).insert(_overlayEntry!);
      _isVisible = true;
    });
  }

  /// 隐藏提示弹窗
  static void hide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (_isVisible && _overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _isVisible = false;
    }
  }

  /// 获取当前是否显示
  static bool get isVisible => _isVisible;
}

class _TooltipContent extends StatefulWidget {
  const _TooltipContent({
    required this.title,
    required this.description,
    required this.position,
    required this.isDark,
    required this.onDismiss,
  });

  final String title;
  final String description;
  final Offset position;
  final bool isDark;
  final VoidCallback onDismiss;

  @override
  State<_TooltipContent> createState() => _TooltipContentState();
}

class _TooltipContentState extends State<_TooltipContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF3A3A3A) : const Color(0xFFFFFFFF);
    final textColor =
        widget.isDark ? Colors.white : const Color(0xFF333333);
    final descColor =
        widget.isDark ? Colors.white70 : const Color(0xFF666666);
    final borderColor =
        widget.isDark ? Colors.white12 : Colors.black12;

    return Positioned(
      left: widget.position.dx - 100,
      top: widget.position.dy - 120,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _slide,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '▸ ${widget.title}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '· ${widget.description}',
                      style: TextStyle(
                        color: descColor,
                        fontSize: 12,
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
