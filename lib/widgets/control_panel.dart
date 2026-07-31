import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';
import '../services/notification_service.dart';
import 'base_panel.dart';
import 'tooltip_popup.dart';

/// 控制面板开关项配置
class _ControlSwitch {
  const _ControlSwitch({
    required this.id,
    required this.title,
    required this.icon,
    this.descriptionSpans,
    this.value = true,
    this.onToggle,
  });

  final String id;
  final String title;
  final IconData icon;
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
  bool _enableNotification = true;

  @override
  bool get panelHovered => _panelHovered;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    HomeScreen.settingsChangeNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    HomeScreen.settingsChangeNotifier.removeListener(_onRefresh);
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

  void _toggleNotification() {
    setState(() => _enableNotification = !_enableNotification);
    NotificationService.instance.enabled = _enableNotification;
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
    _ControlSwitch(
      id: 'notification',
      title: '通知推送',
      icon: Icons.notifications_rounded,
      descriptionSpans: [
        const TextSpan(text: '开启后接收系统通知\n'),
        const TextSpan(text: '包括 '),
        TextSpan(
          text: '任务完成',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        const TextSpan(text: '、'),
        TextSpan(
          text: '消息提醒',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        const TextSpan(text: ' 等'),
      ],
      value: _enableNotification,
      onToggle: _toggleNotification,
    ),
    _ControlSwitch(
      id: 'placeholder2',
      title: '自动同步',
      icon: Icons.sync_rounded,
      descriptionSpans: [
        const TextSpan(text: '自动同步数据到云端\n'),
        const TextSpan(text: '支持 '),
        TextSpan(
          text: '实时备份',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        const TextSpan(text: ' 和 '),
        TextSpan(
          text: '跨设备同步',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
      ],
      value: false,
    ),
  ];

  @override
  Widget buildContent(BuildContext context) {
    // 实际内容在 build() 中渲染（需要 MouseRegion 包裹）
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _panelHovered = true),
      onExit: (_) => setState(() => _panelHovered = false),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _items.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _buildSwitchItem(_items[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showTooltip(BuildContext context, _ControlSwitch item, Offset position) {
    TooltipPopup.show(
      context: context,
      title: item.title,
      descriptionSpans: item.descriptionSpans,
      position: position,
      isDark: isDark,
    );
  }

  Widget _buildSwitchItem(_ControlSwitch item) {
    return _ControlItemWidget(
      item: item,
      onShowTooltip: (position) => _showTooltip(context, item, position),
    );
  }
}

class _ControlItemWidget extends StatefulWidget {
  const _ControlItemWidget({
    required this.item,
    required this.onShowTooltip,
  });

  final _ControlSwitch item;
  final Function(Offset) onShowTooltip;

  @override
  State<_ControlItemWidget> createState() => _ControlItemWidgetState();
}

class _ControlItemWidgetState extends State<_ControlItemWidget> {
  @override
  Widget build(BuildContext context) {
    final enabled = widget.item.value;

    return MouseRegion(
      onHover: (event) {
        widget.onShowTooltip(event.position);
      },
      onExit: (_) {
        TooltipPopup.hide();
      },
      child: GestureDetector(
        onTap: widget.item.onToggle,
        child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 30,
              spreadRadius: 4,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
            children: [
              Icon(
                widget.item.icon,
                color: enabled ? Colors.greenAccent : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.item.title,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: enabled
                      ? Colors.greenAccent.withOpacity(0.9)
                      : Colors.white.withOpacity(0.15),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: enabled ? Colors.white : Colors.white54,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
