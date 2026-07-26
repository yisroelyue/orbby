import 'package:flutter/material.dart';

import '../config/panel_theme.dart';

/// 面板尺寸：small 占半宽，full 占满宽
enum PanelSize { small, full }

/// 面板基类，提供统一的容器和主题样式
///
/// 子类需实现 [buildContent]。
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求

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
