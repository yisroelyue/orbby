/// 面板数据内存缓存，应用重启后丢失
class PanelCache {
  PanelCache._();

  static final Map<String, dynamic> _data = {};

  static T? get<T>(String key) => _data[key] as T?;

  static void set(String key, dynamic value) => _data[key] = value;

  static bool has(String key) => _data.containsKey(key);
}
