import 'package:flutter/foundation.dart';

/// 面板数据内存缓存，应用重启后丢失
///
/// 通过 [addListener]/[removeListener] 监听数据变化，
/// 面板应在 [State.initState] 注册、[State.dispose] 注销。
class PanelCache {
  PanelCache._();

  static final Map<String, dynamic> _data = {};
  static final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  static T? get<T>(String key) => _data[key] as T?;

  static void set(String key, dynamic value) {
    _data[key] = value;
    _notifier.value++; // 通知所有监听者
  }

  static bool has(String key) => _data.containsKey(key);

  /// 监听缓存变化，面板在 initState 注册，dispose 注销
  static void addListener(VoidCallback listener) =>
      _notifier.addListener(listener);

  static void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);
}
