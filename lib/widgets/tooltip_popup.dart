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
    String? description,
    List<InlineSpan>? descriptionSpans,
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
          descriptionSpans: descriptionSpans,
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
    this.description,
    this.descriptionSpans,
    required this.position,
    required this.isDark,
    required this.onDismiss,
  });

  final String title;
  final String? description;
  final List<InlineSpan>? descriptionSpans;
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
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
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
        widget.isDark ? const Color(0xFF2A2D3E) : const Color(0xFFFFFFFF);
    final textColor =
        widget.isDark ? Colors.white : const Color(0xFF1A1A2E);
    final descColor =
        widget.isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF555555);
    final borderColor =
        widget.isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08);
    final accentColor =
        widget.isDark ? const Color(0xFF6C63FF) : const Color(0xFF5B5FC7);
    final dividerColor =
        widget.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06);

    return Positioned(
      left: widget.position.dx - 110,
      top: widget.position.dy - 130,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 220,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 16,
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 分割线
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              dividerColor,
                              dividerColor,
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.2, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // 描述内容
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: widget.descriptionSpans != null
                          ? RichText(
                              text: TextSpan(
                                children: widget.descriptionSpans,
                                style: TextStyle(
                                  color: descColor,
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                            )
                          : widget.description != null
                              ? Text(
                                  widget.description!,
                                  style: TextStyle(
                                    color: descColor,
                                    fontSize: 12,
                                    height: 1.6,
                                  ),
                                )
                              : const SizedBox.shrink(),
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
