import 'package:flutter/material.dart';

import '../config/panel_theme.dart';
import '../config/settings.dart';
import '../screens/home_screen.dart';
import 'base_panel.dart';
import 'tooltip_popup.dart';

/// 控制面板开关项配置
class _ControlSwitch {
  const _ControlSwitch({
    required this.id,
    required this.title,
    required this.icon,
    this.description,
    this.descriptionSpans,
    this.value = true,
    this.onToggle,
  });

  final String id;
  final String title;
  final IconData icon;
  final String? description;
  final List<InlineSpan>? descriptionSpans;

  /// 当前开关状态
  final bool value;

  /// 点击回调（null 时不可点击）
  final VoidCallback? onToggle;
}

/// 控制面板组件
class ControlPanel extends BasePanel {
  const ControlPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'control';

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends BasePanelState<ControlPanel> {
  static const _primaryColor = Color(0xFF2196F3);
  bool _panelHovered = false;
  bool _showVibePanel = true;
  bool _enableClipboard = false;

  @override
  bool get panelHovered => _panelHovered;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    HomeScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    HomeScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _showVibePanel = settings.showVibePanel;
      _enableClipboard = settings.enableClipboardMonitor;
    });
  }

  void _onRefresh() {
    _loadSettings();
  }

  Future<void> _toggleClipboard() async {
    final settings = await SettingsService.load();
    settings.enableClipboardMonitor = !settings.enableClipboardMonitor;
    await SettingsService.save(settings);
    if (!mounted) return;
    setState(() => _enableClipboard = settings.enableClipboardMonitor);
    HomeScreen.menuChannel.invokeMethod('toggle_clipboard_monitor');
  }

  Future<void> _toggleVibePanel() async {
    final settings = await SettingsService.load();
    settings.showVibePanel = !settings.showVibePanel;
    await SettingsService.save(settings);
    if (!mounted) return;
    setState(() => _showVibePanel = settings.showVibePanel);
    HomeScreen.menuChannel.invokeMethod('toggle_vibe_panel');
  }

  /// 构建当前控制项列表（依赖运行时状态）
  List<_ControlSwitch> get _items => [
    _ControlSwitch(
      id: 'clipboard',
      title: '快速剪切板',
      icon: Icons.content_paste_rounded,
      descriptionSpans: [
        const TextSpan(text: '监听剪切板变化，自动保存复制内容\n'),
        const TextSpan(text: '按 '),
        TextSpan(
          text: 'Ctrl+Shift+V',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        const TextSpan(text: ' 打开历史记录\n选择后自动复制到剪贴板'),
      ],
      value: _enableClipboard,
      onToggle: _toggleClipboard,
    ),
    _ControlSwitch(
      id: 'vibe',
      title: 'Claude 监测',
      icon: Icons.tv,
      descriptionSpans: [
        const TextSpan(text: '实时监控 '),
        TextSpan(
          text: 'Claude Code',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        const TextSpan(text: ' 任务状态\n'),
        const TextSpan(text: '自动检测 '),
        TextSpan(
          text: 'Hook 事件',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        const TextSpan(text: ' 并更新进度，状态'),
      ],
      value: _showVibePanel,
      onToggle: _toggleVibePanel,
    ),
  ];

  @override
  Widget buildContent(BuildContext context) {
    // 实际内容在 build() 中渲染（需要 MouseRegion 包裹）
    return const SizedBox.shrink();
  }

  void _showTooltip(BuildContext context, _ControlSwitch item, Offset position) {
    TooltipPopup.show(
      context: context,
      title: item.title,
      description: item.description,
      descriptionSpans: item.descriptionSpans,
      position: position,
      isDark: isDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _panelHovered = true),
      onExit: (_) => setState(() => _panelHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BasePanelState.panelBorderRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          color: panelBg,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _items.map((item) => _buildSwitchItem(item)).toList(),
      ),
    );
  }

  Widget _buildSwitchItem(_ControlSwitch item) {
    return _ControlItemWidget(
      item: item,
      iconColor: secondaryText,
      titleColor: primaryText,
      hoverBg: hoverBg,
      onShowTooltip: (position) => _showTooltip(context, item, position),
    );
  }
}

class _ControlItemWidget extends StatefulWidget {
  const _ControlItemWidget({
    required this.item,
    required this.iconColor,
    required this.titleColor,
    required this.hoverBg,
    required this.onShowTooltip,
  });

  final _ControlSwitch item;
  final Color iconColor;
  final Color titleColor;
  final Color hoverBg;
  final ValueChanged<Offset> onShowTooltip;

  @override
  State<_ControlItemWidget> createState() => _ControlItemWidgetState();
}

class _ControlItemWidgetState extends State<_ControlItemWidget> with PanelThemeMixin {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.item.value;

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 200),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovered = true);
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.attached) {
            final position = renderBox.localToGlobal(
              Offset(renderBox.size.width / 2, 0),
            );
            widget.onShowTooltip(position);
          }
        },
        onExit: (_) {
          setState(() => _hovered = false);
          TooltipPopup.hide();
        },
        child: GestureDetector(
          onTap: widget.item.onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverBg : elementBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered
                    ? (enabled
                        ? Colors.greenAccent.withOpacity(0.2)
                        : Colors.white.withOpacity(0.06))
                    : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.item.icon,
                  color: enabled ? Colors.greenAccent : widget.iconColor,
                  size: 20,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.item.title,
                  style: TextStyle(
                    color: enabled ? widget.titleColor : widget.iconColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: enabled ? Colors.greenAccent : Colors.white24,
                    shape: BoxShape.circle,
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
