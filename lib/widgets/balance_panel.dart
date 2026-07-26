import 'package:flutter/material.dart';

import '../config/platform.dart';
import '../config/settings.dart';
import '../screens/home_screen.dart';
import '../services/balance_service.dart';
import '../services/panel_cache.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class BalancePanel extends BasePanel {
  const BalancePanel({super.key});

  @override
  String get panelName => 'balance';

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
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  void initState() {
    super.initState();

    // 先从缓存恢复数据
    final cachedBalance = PanelCache.get<BalanceInfo>('balance_info');
    final cachedConnected = PanelCache.get<bool>('balance_connected') ?? false;
    if (cachedBalance != null) {
      _balance = cachedBalance;
      _loading = false;
      _connected = cachedConnected;
    }

    HomeScreen.refreshNotifier.addListener(_onRefresh);
    registerPanelEnabled((v) => _panelEnabled = v, (s) => s.showBalancePanel);

    if (cachedBalance != null) {
      // 有缓存只读设置，不做连通性测试
      _loadSettings();
    } else {
      // 无缓存才做连通性测试（会内部读取设置）
      _initialTestDone = true;
      _testConnectivity();
    }
  }

  @override
  void dispose() {
    HomeScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (_balance != null) {
      // 有缓存只刷新设置，不做连通性测试
      _loadSettings();
    } else {
      _testConnectivity();
    }
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _platform = settings.platform;
      _panelEnabled = settings.showBalancePanel;
      _enableBalance = settings.enableBalance;
      _notConfigured = settings.apiKey.isEmpty;
      // 有缓存时不显示 loading
      if (_balance != null) _loading = false;
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
      PanelCache.set('balance_connected', false);
      setState(() => _loading = false);
      return;
    }
    if (settings.apiKey.isEmpty) {
      if (!mounted) return;
      PanelCache.set('balance_connected', false);
      setState(() {
        _notConfigured = true;
        _loading = false;
      });
      return;
    }

    final ok = await BalanceService.testConnectivity();
    if (!mounted) return;
    _connected = ok;
    PanelCache.set('balance_connected', ok);

    if (_enableBalance && ok) {
      try {
        final balance = await BalanceService.fetchBalance();
        PanelCache.set('balance_info', balance);
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
      BalanceInfo balanceInfo = BalanceInfo(isAvailable: true, totalBalance: 0, grantedBalance: 0, toppedUpBalance: 0, currency: "0");
      PanelCache.set('balance_info',balanceInfo);
    }
  }

  @override
  Widget buildContent(BuildContext context) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题栏
        _BalanceHeader(
          icon: _loading
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
          title: PlatformConfig.platforms[_platform]?.name ?? 'AI 流量',
          titleColor: primaryText,
          mutedText: mutedText,
          statusColor: statusColor,
          statusText: statusText,
          secondaryText: secondaryText,
          actions: [
            InteractiveIcon(
              size: 32,
              onTap: _testConnectivity,
              child: Icon(Icons.refresh_rounded, color: tertiaryText, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 内容区域
        if (_loading) ...[
          Text('检测中...', style: TextStyle(color: mutedText, fontSize: 14)),
        ] else if (_notConfigured) ...[
          Column(
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
          ),
        ] else if (!_connected) ...[
          Column(
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
          ),
        ] else if (_enableBalance && _balance != null) ...[
          Builder(
            builder: (context) {
              final b = _balance!;
              final symbol = b.currency == 'USD' ? '\$' : '¥';
              // TODO: 替换为真实用量数据
              const usedPercent = 0.37;
              final accent = isDark
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF2979FF);
              final trackColor = isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.05);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // 余额数值
                    Text(
                      '$symbol ${b.totalBalance.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 用量进度条 + 百分比
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${(usedPercent * 100).toStringAsFixed(0)}% 已使用',
                            style: TextStyle(
                              color: tertiaryText,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 6,
                              child: Stack(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    color: trackColor,
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: usedPercent,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            accent.withOpacity(0.6),
                                            accent,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ] else ...[
          Builder(
            builder: (context) {
              final symbol = _balance?.currency == 'USD' ? '\$' : '¥';
              final accent = isDark
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF2979FF);
              final trackColor = isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.05);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // 余额数值
                    Text(
                      '$symbol 0.00',
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 用量进度条 + 百分比
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '0% 已使用',
                            style: TextStyle(
                              color: tertiaryText,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 6,
                              child: Container(
                                width: double.infinity,
                                color: trackColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// BalancePanel 专用 header，带状态指示器（不可点击）
class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({
    required this.icon,
    required this.title,
    required this.titleColor,
    required this.mutedText,
    required this.statusColor,
    required this.statusText,
    required this.secondaryText,
    this.actions = const [],
  });

  final Widget icon;
  final String title;
  final Color titleColor;
  final Color mutedText;
  final Color statusColor;
  final String statusText;
  final Color secondaryText;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: titleColor,
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
          ...actions,
        ],
      ),
    );
  }
}
