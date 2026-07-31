import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../config/panel_theme.dart';
import '../services/notification_service.dart';

/// 通知独立窗口 — 跟随悬浮球，像对话气泡，一次只显示一条
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  static final messageNotifier = ValueNotifier<_NotifMessage?>(null);

  static void handleMessage(String method, dynamic arguments) {
    messageNotifier.value = _NotifMessage(method: method, arguments: arguments);
  }

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotifMessage {
  final String method;
  final dynamic arguments;
  _NotifMessage({required this.method, required this.arguments});
}

class _NotificationScreenState extends State<NotificationScreen>
    with PanelThemeMixin {
  /// 当前显示的通知（同时只显示一条）
  _NotifEntry? _current;
  Timer? _timer;
  bool _pendingReposition = false;
  /// 悬浮球是否在屏幕右侧（决定文字靠左还是靠右）
  bool _petOnRight = true;

  @override
  void initState() {
    super.initState();
    NotificationScreen.messageNotifier.addListener(_onMessage);
  }

  @override
  void dispose() {
    NotificationScreen.messageNotifier.removeListener(_onMessage);
    _timer?.cancel();
    super.dispose();
  }

  void _onMessage() {
    final msg = NotificationScreen.messageNotifier.value;
    if (msg == null) return;
    NotificationScreen.messageNotifier.value = null;

    switch (msg.method) {
      case 'show':
        final args = msg.arguments as Map;
        _repositionWindow(args);
        _showEntry(
          id: args['id'] as String,
          title: args['title'] as String,
          message: (args['message'] as String?) ?? '',
          level: NotificationLevel.values[args['level'] as int],
          iconCodePoint: args['iconCodePoint'] as int?,
          durationMs: args['durationMs'] as int,
        );
        return;
      case 'dismiss':
        _clear();
        return;
      case 'clear':
        _clear();
        return;
    }
  }

  void _repositionWindow(Map args) {
    final petX = (args['petX'] as num?)?.toDouble() ?? 0;
    final petY = (args['petY'] as num?)?.toDouble() ?? 0;
    final petW = (args['petW'] as num?)?.toDouble() ?? 100;
    final petH = (args['petH'] as num?)?.toDouble() ?? 100;
    final screenW = (args['screenW'] as num?)?.toDouble() ?? 1920;
    final screenH = (args['screenH'] as num?)?.toDouble() ?? 1080;

    // 单条消息窗口尺寸
    const notifW = 380.0;
    const notifH = 52.0;

    final petCenterX = petX + petW / 2;
    final petCenterY = petY + petH / 2;

    double notifX, notifY;

    _petOnRight = petCenterX > screenW / 2;

    if (_petOnRight) {
      notifX = petX - notifW - 12;
    } else {
      notifX = petX + petW + 12;
    }
    notifY = petCenterY - notifH / 2;

    notifX = notifX.clamp(0.0, math.max(0, screenW - notifW));
    notifY = notifY.clamp(0.0, math.max(0, screenH - notifH));

    if (_pendingReposition) return;
    _pendingReposition = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingReposition = false;
      try {
        windowManager.setBounds(Rect.fromLTWH(notifX, notifY, notifW, notifH));
        windowManager.show();
      } catch (_) {}
    });
  }

  void _showEntry({
    required String id,
    required String title,
    required String message,
    required NotificationLevel level,
    int? iconCodePoint,
    required int durationMs,
  }) {
    _timer?.cancel();

    final entry = _NotifEntry(
      id: id,
      title: title,
      message: message,
      level: level,
      icon: iconCodePoint != null
          ? IconData(iconCodePoint, fontFamily: 'MaterialIcons')
          : null,
    );

    setState(() => _current = entry);

    if (durationMs > 0) {
      _timer = Timer(Duration(milliseconds: durationMs), _clear);
    }
  }

  void _clear() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _current = null);
    try {
      windowManager.hide();
    } catch (_) {}
  }

  // ─── 构建 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_current == null) return const SizedBox.shrink();

    final entry = _current!;
    final dark = isDark;
    // 合并 title + message 为一条消息
    final text = entry.message.isNotEmpty ? entry.message : entry.title;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: _petOnRight ? Alignment.centerRight : Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(12 * (1 - value), 0),
                child: child,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: dark ? const Color(0xE5282C3A) : const Color(0xE5E8E8E8),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(dark ? 0.25 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: dark ? const Color(0xFFE8E8E8) : const Color(0xFF333333),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotifEntry {
  final String id;
  final String title;
  final String message;
  final NotificationLevel level;
  final IconData? icon;

  _NotifEntry({
    required this.id,
    required this.title,
    required this.message,
    required this.level,
    this.icon,
  });
}
