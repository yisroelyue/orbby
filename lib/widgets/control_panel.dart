import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/panel_theme.dart';
import '../config/settings.dart';
import '../screens/menu_screen.dart';
import 'tooltip_popup.dart';

/// 控制面板开关项配置
class _ControlSwitch {
  const _ControlSwitch({
    required this.id,
    required this.title,
    required this.icon,
    required this.description,
    this.value = true,
    this.onToggle,
  });

  final String id;
  final String title;
  final IconData icon;
  final String description;

  /// 当前开关状态
  final bool value;

  /// 点击回调（null 时不可点击）
  final VoidCallback? onToggle;
}

/// 控制面板组件
class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> with PanelThemeMixin {
  bool _headerHovered = false;
  bool _panelHovered = false;
  bool _panelEnabled = true;
  bool _showVibePanel = true;
  bool _enableClipboard = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    MenuScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _panelEnabled = settings.showControlPanel;
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
  }

  Future<void> _toggleVibePanel() async {
    final settings = await SettingsService.load();
    settings.showVibePanel = !settings.showVibePanel;
    await SettingsService.save(settings);
    if (!mounted) return;
    setState(() => _showVibePanel = settings.showVibePanel);
    MenuScreen.menuChannel.invokeMethod('toggle_vibe_panel');
  }

  /// 构建当前控制项列表（依赖运行时状态）
  List<_ControlSwitch> get _items => [
    _ControlSwitch(
      id: 'clipboard',
      title: '快速剪切板',
      icon: Icons.content_paste_rounded,
      description: '监听剪切板变化，自动保存复制内容到历史记录，方便快速查找和复用',
      value: _enableClipboard,
      onToggle: _toggleClipboard,
    ),
    _ControlSwitch(
      id: 'vibe',
      title: 'Claude 监测',
      icon: Icons.tv,
      description: '开启或关闭 Vibe Coding 状态条，显示 Claude Code 任务进度',
      value: _showVibePanel,
      onToggle: _toggleVibePanel,
    ),
  ];

  void _showTooltip(BuildContext context, _ControlSwitch item, Offset position) {
    TooltipPopup.show(
      context: context,
      title: item.title,
      description: item.description,
      position: position,
      isDark: isDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_panelEnabled) {
      return const SizedBox.shrink();
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _panelHovered = true),
      onExit: (_) => setState(() => _panelHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          color: panelBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    MenuScreen.menuChannel.invokeMethod('open_settings');
  }

  Widget _buildHeader() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _headerHovered = true),
      onExit: (_) => setState(() => _headerHovered = false),
      child: GestureDetector(
        onTap: _openSettings,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _headerHovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/svg/控制.svg',
                width: 22,
                height: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '控制面板',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _headerHovered ? 1.0 : 0.0,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: mutedText,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // 默认显示一行（2个），hover 时显示全部
    final visibleItems = _panelHovered ? _items : _items.take(2).toList();
    final rowCount = (visibleItems.length / 2).ceil();
    final rows = <Widget>[];

    for (var i = 0; i < rowCount; i++) {
      final startIndex = i * 2;
      final endIndex = (startIndex + 2).clamp(0, visibleItems.length);
      final rowItems = visibleItems.sublist(startIndex, endIndex);

      rows.add(_buildRow(rowItems));
      if (i < rowCount - 1) {
        rows.add(const SizedBox(height: 10));
      }
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(children: rows),
    );
  }

  Widget _buildRow(List<_ControlSwitch> items) {
    return Row(
      children: [
        Expanded(child: _buildSwitchItem(items[0])),
        const SizedBox(width: 10),
        if (items.length > 1)
          Expanded(child: _buildSwitchItem(items[1]))
        else
          const Expanded(child: SizedBox()),
      ],
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

class _ControlItemWidgetState extends State<_ControlItemWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.item.value;

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovered = true);
          // 获取位置并显示 tooltip
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                AnimatedScale(
                  scale: _hovered ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    widget.item.icon,
                    color: widget.iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                      color: widget.titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    child: Text(widget.item.title),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: enabled ? Colors.greenAccent : Colors.black38,
                    shape: BoxShape.circle,
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
