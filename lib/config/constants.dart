/// 悬浮球配置常量
class PetConfig {
  PetConfig._();

  /// 悬浮球尺寸
  static const double ballSize = 32.0;

  /// 内层圆角矩形尺寸（仅悬浮球）
  static const double innerWidth = ballSize;
  static const double innerHeight = ballSize;
  static const double innerRadius = 16;

  /// 外层矩形窗口尺寸（含 padding）
  static const double windowPaddingH = 12.0;
  static const double windowPaddingV = 12.0;
  static const double windowWidth = innerWidth + windowPaddingH * 2;
  static const double windowHeight = innerHeight + windowPaddingV * 2;

  /// 悬浮球图标资源路径
  static const String logoSprite = 'assets/png/logo.png';
}

