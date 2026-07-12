import 'sub_app.dart';

/// 静态注册表，采用工厂函数模式：
/// 注册时传入构造函数，启动时才实例化，避免所有子应用在启动时全部初始化。
class SubAppRegistry {
  SubAppRegistry._();

  static final Map<String, SubApp Function()> _factories = {};

  /// 由各子应用 package 在启动时调用，自我注册。
  static void register(SubApp Function() factory) {
    final instance = factory();
    _factories[instance.id] = factory;
  }

  /// 获取所有已注册子应用的元数据（每个调用一次工厂获取信息）。
  static List<SubApp> get all =>
      _factories.values.map((f) => f()).toList();

  /// 按 ID 查找子应用实例。
  static SubApp? byId(String id) => _factories[id]?.call();

  /// 检查是否有指定 ID 的子应用。
  static bool exists(String id) => _factories.containsKey(id);
}
