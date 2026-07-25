import 'package:flutter/material.dart';

import '../config/platform.dart';
import '../config/settings.dart';
import '../screens/menu_screen.dart';
import '../services/balance_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class BalancePanel extends BasePanel {
  const BalancePanel({super.key});

  @override
  State<BalancePanel> createState() => BalancePanelState();
}

class BalancePanelState extends BasePanelState<BalancePanel> {
  BalanceInfo? _balance;
  String _platform = 'deepseek';
  bool _panelEnabled = true;
  bool _enableBalance = true;
  bool _notConfigured = false;
  bool _connected = false;
  bool _loading = true;
  bool _initialTestDone = false;

  @override
  String get panelTitle => PlatformConfig.platforms[_platform]?.name ?? 'AI 流量';

  @override
  PanelIcon get panelIcon => PanelIcon.widget(
    _loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tertiaryText,
            ),
          )
        : Image.asset(
            PlatformConfig.assetPath(_platform),
            width: 22,
            height: 22,
          ),
  );

  @override
  VoidCallback? get onHeaderTap => _openSettings;

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    MenuScreen.refreshNotifier.addListener(_onRefresh);
    if (!_initialTestDone) {
      _initialTestDone = true;
      _testConnectivity();
    }
  }

  @override
  void dispose() {
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _platform = settings.platform;
      _panelEnabled = settings.showBalancePanel;
      _enableBalance = settings.enableBalance;
      _notConfigured = settings.apiKey.isEmpty;
    });
  }

  Future<void> _testConnectivity() async {
    setState(() {
      _loading = true;
      _connected = false;
    });

    final settings = await SettingsService.load();
    _platform = settings.platform;
    _panelEnabled = settings.showBalancePanel;
    _enableBalance = settings.enableBalance;
    if (!_panelEnabled) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    if (settings.apiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _notConfigured = true;
        _loading = false;
      });
      return;
    }

    final ok = await BalanceService.testConnectivity();
    if (!mounted) return;
    _connected = ok;

    if (_enableBalance && ok) {
      try {
        final balance = await BalanceService.fetchBalance();
        if (!mounted) return;
        setState(() {
          _balance = balance;
          _loading = false;
        });
      } catch (e) {
        debugPrint('余额获取失败: $e');
        if (!mounted) return;
        setState(() => _loading = false);
      }
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  List<Widget> buildHeaderActions() {
    return [
      InteractiveIcon(
        size: 32,
        onTap: _testConnectivity,
        child: Icon(Icons.refresh_rounded, color: tertiaryText, size: 20),
      ),
    ];
  }

  void _openSettings() {
    MenuScreen.menuChannel.invokeMethod('open_settings');
  }

  @override
  Widget buildHeader() {
    Color statusColor;
    String statusText;
    if (_notConfigured) {
      statusColor = Colors.grey;
      statusText = '未配置';
    } else if (_loading) {
      statusColor = Colors.grey;
      statusText = '...';
    } else if (_connected) {
      statusColor = Colors.greenAccent;
      statusText = '可用';
    } else {
      statusColor = Colors.orangeAccent;
      statusText = '不可用';
    }

    return _BalanceHeader(
      icon: buildIconWidget(),
      title: panelTitle,
      titleColor: primaryText,
      hoverBg: hoverBg,
      mutedText: mutedText,
      statusColor: statusColor,
      statusText: statusText,
      secondaryText: secondaryText,
      onTap: _openSettings,
      actions: buildHeaderActions(),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Text('检测中...', style: TextStyle(color: mutedText, fontSize: 14));
    }
    if (_notConfigured) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '请先配置 API Key',
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _testConnectivity,
            child: Text(
              '点击重试',
              style: TextStyle(color: tertiaryText, fontSize: 12),
            ),
          ),
        ],
      );
    }
    if (!_connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '连接失败，请检查配置',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _testConnectivity,
            child: Text(
              '点击重试',
              style: TextStyle(color: tertiaryText, fontSize: 12),
            ),
          ),
        ],
      );
    }

    if (_enableBalance && _balance != null) {
      final b = _balance!;
      final symbol = b.currency == 'USD' ? '\$' : '¥';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              '$symbol ${b.totalBalance.toStringAsFixed(2)}',
              style: TextStyle(
                color: primaryText,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 10),
          child: Text(
            '暂无API余额信息',
            style: TextStyle(color: mutedText, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// BalancePanel 专用 header，带状态指示器
class _BalanceHeader extends StatefulWidget {
  const _BalanceHeader({
    required this.icon,
    required this.title,
    required this.titleColor,
    required this.hoverBg,
    required this.mutedText,
    required this.statusColor,
    required this.statusText,
    required this.secondaryText,
    this.onTap,
    this.actions = const [],
  });

  final Widget icon;
  final String title;
  final Color titleColor;
  final Color hoverBg;
  final Color mutedText;
  final Color statusColor;
  final String statusText;
  final Color secondaryText;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  State<_BalanceHeader> createState() => _BalanceHeaderState();
}

class _BalanceHeaderState extends State<_BalanceHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
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
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                widget.statusText,
                style: TextStyle(color: widget.secondaryText, fontSize: 13),
              ),
              const SizedBox(width: 6),
              ...widget.actions,
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
