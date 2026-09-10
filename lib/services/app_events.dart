import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

/// 全局事件总线：跨窗口（跨 Flutter engine）与窗口内组件统一使用。
///
/// 路由：emit 先通知本窗口监听者；子窗口再上报主窗口（hub），hub 转发给
/// 所有子窗口，子窗口收到后本地通知。监听方无需关心事件来自哪个窗口。
/// 窗口控制类指令（place、hidden、open_app_center 等）不走此总线，
/// 仍用定向 channel。
class AppEvents {
  AppEvents._();

  // ---- 事件名集中定义，禁止散落魔法字符串 ----

  /// 设置已保存（主题、API、翻译等）
  static const settingsChanged = 'settings_changed';

  /// 应用或面板应用列表发生变化
  static const panelAppsChanged = 'panel_apps_changed';

  static const _channel = WindowMethodChannel(
    'orbby_app_events',
    mode: ChannelMode.unidirectional,
  );

  static final _listeners = <String, Set<VoidCallback>>{};
  static bool _isHub = false;
  static void Function(String event)? _broadcast;

  /// 主窗口启动时调用一次：注册为 hub，broadcast 由 WindowCoordinator 提供
  static Future<void> initHub(void Function(String event) broadcast) async {
    _isHub = true;
    _broadcast = broadcast;
    await _channel.setMethodCallHandler((call) async {
      if (call.method == 'post') {
        final event = call.arguments as String;
        _notify(event);
        broadcast(event);
      }
    });
  }

  /// 广播事件：本窗口立即生效，并扩散到所有窗口
  static Future<void> emit(String event) async {
    _notify(event);
    if (_isHub) {
      _broadcast?.call(event);
      return;
    }
    try {
      await _channel.invokeMethod('post', event);
    } catch (_) {
      // hub 未就绪时忽略，本窗口已生效
    }
  }

  /// 子窗口收到 hub 转发时调用（main.dart 各窗口 handler 中）
  static void receive(String event) => _notify(event);

  static void addListener(String event, VoidCallback callback) =>
      (_listeners[event] ??= {}).add(callback);

  static void removeListener(String event, VoidCallback callback) =>
      _listeners[event]?.remove(callback);

  static void _notify(String event) =>
      _listeners[event]?.toList().forEach((cb) => cb());
}
