import 'package:flutter/material.dart';

import '../config/panel_theme.dart';
import '../config/settings.dart';
import '../screens/home_screen.dart';

/// 面板尺寸：small 占半宽，full 占满宽
enum PanelSize { small, full }

/// 面板基类，提供统一的容器和主题样式
///
/// 子类需实现 [buildContent]。
/// 可选覆写 [panelEnabled]。
abstract class BasePanel extends StatefulWidget {
  const BasePanel({super.key});

  /// 面板尺寸，small 占半宽，full 占满宽
  /// 子类可覆写，默认 full
  PanelSize get panelSize => PanelSize.full;

  /// 面板唯一标识，子类必须覆写
  String get panelName;

  @override
  State<BasePanel> createState();
}

abstract class BasePanelState<T extends BasePanel> extends State<T>
    with PanelThemeMixin, AutomaticKeepAliveClientMixin {
  /// 面板是否启用（用于决定是否显示 SizedBox.shrink）
  bool get panelEnabled => true;

  @override
  bool get wantKeepAlive => true;

  /// 面板内容区域
  Widget buildContent(BuildContext context);

  /// 面板整体是否处于 hover 状态（用于内容区域展开/收起）
  /// 子类可覆写以支持 hover 展开逻辑
  bool get panelHovered => false;

  /// 面板外层圆角
  static const double panelBorderRadius = 16;

  /// 面板自定义装饰，子类可覆写以自定义背景样式
  /// 返回 null 时使用默认的 panelBg 纯色背景
  BoxDecoration? get panelDecoration => null;

  /// 面板内边距，子类可覆写
  EdgeInsetsGeometry get panelPadding => const EdgeInsets.all(16);

  bool _listeningSettings = false;
  void Function(bool)? _panelEnabledSetter;

  /// 子类在 initState 中调用，注册面板开关的读写
  /// [setter] 直接赋值子类的 _panelEnabled 字段
  /// [settingsKey] 从 AppSettings 中读取对应字段
  void registerPanelEnabled(
    void Function(bool) setter,
    bool Function(AppSettings) settingsKey,
  ) {
    _panelEnabledSetter = (value) {
      setter(value);
      if (mounted) setState(() {});
    };
    _settingsKey = settingsKey;
  }

  bool Function(AppSettings)? _settingsKey;

  void _onSettingsChanged() async {
    if (_panelEnabledSetter == null || _settingsKey == null) return;
    final s = await SettingsService.load();
    if (!mounted) return;
    _panelEnabledSetter!(_settingsKey!(s));
  }

  @override
  void dispose() {
    if (_listeningSettings) {
      HomeScreen.settingsChangeNotifier.removeListener(_onSettingsChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求

    if (!_listeningSettings && _panelEnabledSetter != null) {
      _listeningSettings = true;
      HomeScreen.settingsChangeNotifier.addListener(_onSettingsChanged);
    }

    if (!panelEnabled) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(panelBorderRadius),
      child: Container(
        padding: panelPadding,
        decoration: panelDecoration ??
            BoxDecoration(
              color: panelBg,
            ),
        child: buildContent(context),
      ),
    );
  }
}
