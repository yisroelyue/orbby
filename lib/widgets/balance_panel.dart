import 'package:flutter/material.dart';

import '../config/platform.dart';
import '../config/settings.dart';
import '../config/panel_theme.dart';
import '../screens/menu_screen.dart';
import '../services/balance_service.dart';
import 'interactive_icon.dart';

class BalancePanel extends StatefulWidget {
  const BalancePanel({super.key});

  @override
  State<BalancePanel> createState() => BalancePanelState();
}

class BalancePanelState extends State<BalancePanel> with PanelThemeMixin {
  BalanceInfo? _balance;
  String _platform = 'deepseek';
  bool _panelEnabled = true;
  bool _enableBalance = true;
  bool _notConfigured = false;
  bool _connected = false;
  bool _loading = true;
  bool _headerHovered = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    MenuScreen.refreshNotifier.addListener(_onRefresh);
    // 程序启动时测试连通性
    _testConnectivity();
  }

  @override
  void dispose() {
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _loadSettings();
    // 只有点击刷新按钮时才测试连通性
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

    // 测试连通性
    final ok = await BalanceService.testConnectivity();
    if (!mounted) return;
    _connected = ok;

    // 如果开启了余额查询且连通，再获取余额
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

  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InteractiveIcon(
          size: 32,
          onTap: _testConnectivity,
          child: Icon(Icons.refresh_rounded, color: tertiaryText, size: 20),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_panelEnabled && !_loading) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: panelBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
            const SizedBox(height: 6),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    MenuScreen.menuChannel.invokeMethod('open_settings');
  }

  Widget _buildHeader() {
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
              if (_loading)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tertiaryText,
                  ),
                )
              else
                Image.asset(
                  PlatformConfig.assetPath(_platform),
                  width: 22,
                  height: 22,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  PlatformConfig.platforms[_platform]?.name ?? 'AI 流量',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: TextStyle(color: secondaryText, fontSize: 13),
              ),
              const SizedBox(width: 6),
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

    // 连通成功
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

          _buildActionButtons(),
        ],
      );
    }

    // 连通但未开启余额
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20,bottom: 10),
          child: Text(
            '暂无API余额信息',
            style: TextStyle(color: mutedText, fontSize: 14,fontWeight:  FontWeight.w600,),
          ),
        ),
        _buildActionButtons(),
      ],
    );
  }
}
