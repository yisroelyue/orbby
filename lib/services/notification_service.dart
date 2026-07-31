import 'dart:async';

import 'package:flutter/material.dart';

/// 通知级别
enum NotificationLevel { info, success, warning, error }

/// 单条通知数据（可序列化，用于跨窗口传输）
class NotificationItem {
  final String id;
  final String title;
  final String message;
  final NotificationLevel level;
  final int? iconCodePoint;
  final int durationMs;
  final bool hasOnTap;

  NotificationItem({
    required this.id,
    required this.title,
    this.message = '',
    this.level = NotificationLevel.info,
    this.iconCodePoint,
    this.durationMs = 4000,
    this.hasOnTap = false,
  });
}

/// 全局通知服务
///
/// 通知通过独立窗口显示在屏幕右下角，始终置顶。
///
/// 用法：
/// ```dart
/// NotificationService.instance.show(
///   title: '任务完成',
///   message: '代码审查已通过',
///   level: NotificationLevel.success,
/// );
/// ```
class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  /// 由 PetScreen 注入，用于向通知窗口发送消息
  Future<void> Function(Map<String, dynamic> data)? _sender;

  void bindSender(Future<void> Function(Map<String, dynamic> data) sender) {
    _sender = sender;
  }

  int _counter = 0;
  Timer? _hideTimer;

  /// 是否启用通知推送
  bool enabled = true;

  /// 通知是否正在显示（用于悬浮球交互状态）
  final ValueNotifier<bool> isShowingNotifier = ValueNotifier(false);

  /// 最大同时显示数量
  static const maxVisible = 5;

  /// 显示一条通知（enabled 为 false 时不发送）
  void show({
    required String title,
    String message = '',
    NotificationLevel level = NotificationLevel.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
  }) {
    if (!enabled) return;

    final id = 'notif_${++_counter}_${DateTime.now().millisecondsSinceEpoch}';

    // 通知悬浮球进入活跃状态
    isShowingNotifier.value = true;
    _hideTimer?.cancel();
    if (duration > Duration.zero) {
      _hideTimer = Timer(duration, () => isShowingNotifier.value = false);
    }

    final data = <String, dynamic>{
      'method': 'show',
      'id': id,
      'title': title,
      'message': message,
      'level': level.index,
      'durationMs': duration.inMilliseconds,
    };
    if (icon != null) {
      data['iconCodePoint'] = icon.codePoint;
    }
    if (onTap != null) {
      data['hasOnTap'] = true;
    }

    _sender?.call(data);
  }

  /// 移除指定通知
  void dismiss(String id) {
    _sender?.call({'method': 'dismiss', 'id': id});
  }

  /// 清空所有通知
  void clear() {
    _sender?.call({'method': 'clear'});
  }
}
