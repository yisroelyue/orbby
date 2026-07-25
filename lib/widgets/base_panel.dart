import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/panel_theme.dart';

/// 面板图标类型
enum PanelIconType { icon, svg, asset, widget }

/// 面板图标配置
class PanelIcon {
  const PanelIcon.icon(this.iconData)
      : type = PanelIconType.icon,
        asset = null,
        widget = null;
  const PanelIcon.svg(this.asset)
      : type = PanelIconType.svg,
        iconData = null,
        widget = null;
  const PanelIcon.asset(this.asset)
      : type = PanelIconType.asset,
        iconData = null,
        widget = null;
  const PanelIcon.widget(this.widget)
      : type = PanelIconType.widget,
        asset = null,
        iconData = null;

  final PanelIconType type;
  final IconData? iconData;
  final String? asset;
  final Widget? widget;
}

/// 面板基类，提供统一的容器、header、主题样式
///
/// 子类需实现 [panelTitle]、[panelIcon]、[buildContent]。
/// 可选覆写 [panelEnabled]、[buildHeaderActions]、[onHeaderTap]。
abstract class BasePanel extends StatefulWidget {
  const BasePanel({super.key});

  @override
  State<BasePanel> createState();
}

abstract class BasePanelState<T extends BasePanel> extends State<T>
    with PanelThemeMixin, AutomaticKeepAliveClientMixin {
  /// 面板是否启用（用于决定是否显示 SizedBox.shrink）
  bool get panelEnabled => true;

  @override
  bool get wantKeepAlive => true;

  /// 面板标题
  String get panelTitle;

  /// 面板图标
  PanelIcon get panelIcon;

  /// 标题行点击回调，null 时不响应点击
  VoidCallback? get onHeaderTap => null;

  /// header 右侧额外操作按钮
  List<Widget> buildHeaderActions() => [];

  /// 面板内容区域
  Widget buildContent(BuildContext context);

  /// 面板整体是否处于 hover 状态（用于内容区域展开/收起）
  /// 子类可覆写以支持 hover 展开逻辑
  bool get panelHovered => false;

  /// 面板外层圆角
  static const double panelBorderRadius = 8;

  /// 面板图标颜色，默认 primaryText
  /// 子类可覆写为 secondaryText 等
  Color get panelIconColor => primaryText;

  /// 构建图标 widget（根据 PanelIcon 类型分发）
  @protected
  Widget buildIconWidget() {
    switch (panelIcon.type) {
      case PanelIconType.icon:
        return Icon(panelIcon.iconData, color: panelIconColor, size: 22);
      case PanelIconType.svg:
        return SvgPicture.asset(
          panelIcon.asset!,
          width: 22,
          height: 22,
        );
      case PanelIconType.asset:
        return Image.asset(
          panelIcon.asset!,
          width: 22,
          height: 22,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.image, color: secondaryText, size: 22),
        );
      case PanelIconType.widget:
        return panelIcon.widget!;
    }
  }

  Widget buildHeader() {
    return _PanelHeader(
      icon: buildIconWidget(),
      title: panelTitle,
      titleColor: primaryText,
      hoverBg: hoverBg,
      mutedText: mutedText,
      onTap: onHeaderTap,
      actions: buildHeaderActions(),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    if (!panelEnabled) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(panelBorderRadius),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: panelBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildHeader(),
            const SizedBox(height: 10),
            buildContent(context),
          ],
        ),
      ),
    );
  }
}

/// 公共 header 组件，封装 hover 动画逻辑
class _PanelHeader extends StatefulWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.titleColor,
    required this.hoverBg,
    required this.mutedText,
    this.onTap,
    this.actions = const [],
  });

  final Widget icon;
  final String title;
  final Color titleColor;
  final Color hoverBg;
  final Color mutedText;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  State<_PanelHeader> createState() => _PanelHeaderState();
}

class _PanelHeaderState extends State<_PanelHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              widget.icon,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: widget.titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...widget.actions,
              if (widget.onTap != null)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1.0 : 0.0,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: widget.mutedText,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
