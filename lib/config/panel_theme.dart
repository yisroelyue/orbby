import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';

mixin PanelThemeMixin<T extends StatefulWidget> on State<T> {
  bool _isDark = true;

  bool get isDark => _isDark;

  Color get light => const Color(0xFFFFFFFF);

  Color get dark => const Color(0xFF636363);

  double get alpha => 1;

  Color get _base => _isDark ? dark : light;

  Color get _baseR => _isDark ? light : dark;

  Color background(double alpha) => _base.withValues(alpha: alpha);

  Color backgroundR(double alpha) => _baseR.withValues(alpha: alpha);

  /// 面板主背景色
  Color get panelBg => background(alpha);

  /// 内层卡片背景（空状态、任务卡片、回答区域）
  Color get cardBg => background(0.06);

  /// 悬停/交互元素背景
  Color get hoverBg => backgroundR(0.05);

  /// 图标背景、分割线
  Color get elementBg => backgroundR(0.05);

  /// 边框
  Color get borderColor => background(0.15);

  /// 输入提示文字
  Color get hintColor => backgroundR(0.7);

  Color get primaryText => _isDark ? Colors.white : const Color(0xFF333333);
  Color get secondaryText => _isDark ? Colors.white70 : const Color(0xFF757575);
  Color get tertiaryText => _isDark ? Colors.white54 : const Color(0xFF9E9E9E);
  Color get mutedText => _isDark ? Colors.white38 : const Color(0xFFBDBDBD);
  Color get faintText => _isDark ? Colors.white30 : const Color(0xFFE0E0E0);
  Color get barelyVisibleText => _isDark ? Colors.white24 : const Color(0xFFF0F0F0);

  /// 强调色，用于选中状态、高亮等
  Color get accentColor => _isDark ? const Color(0xFF6C63FF) : const Color(0xFF5B52E0);

  @override
  void initState() {
    super.initState();
    _loadTheme();
    HomeScreen.settingsChangeNotifier.addListener(_loadTheme);
  }

  @override
  void dispose() {
    HomeScreen.settingsChangeNotifier.removeListener(_loadTheme);
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final s = await SettingsService.load();
    if (!mounted) return;
    setState(() => _isDark = s.appTheme == 'dark');
  }
}
