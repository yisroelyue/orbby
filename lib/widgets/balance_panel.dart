import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/platform.dart';
import '../config/settings.dart';
import '../services/balance_service.dart';
import '../services/cost_record_service.dart';
import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class BalancePanel extends BasePanel {
  const BalancePanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'balance';

  @override
  State<BalancePanel> createState() => BalancePanelState();
}

class BalancePanelState extends BasePanelState<BalancePanel> {
  BalanceInfo? _balance;
  String _platform = 'deepseek';
  bool _enableBalance = true;
  bool _notConfigured = false;
  bool _connected = false;
  bool _loading = true;
  List<DailyCost> _dailyCosts = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadFromCache();
    _loadDailyCosts();
    PanelCache.addListener(_onCacheChanged);
    if (!PanelCache.has('balance_info')) {
      PanelDataService.refreshBalance();
    }
  }

  @override
  void dispose() {
    PanelCache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    _loadFromCache();
    _loadDailyCosts();
  }

  void _loadFromCache() {
    final balance = PanelCache.get<BalanceInfo>('balance_info');
    final connected = PanelCache.get<bool>('balance_connected') ?? false;
    if (mounted) {
      setState(() {
        if (balance != null) {
          _balance = balance;
          _loading = false;
        }
        _connected = connected;
      });
    }
  }

  Future<void> _loadDailyCosts() async {
    final costs = await CostRecordService.getDailyCosts();
    if (mounted) {
      setState(() => _dailyCosts = costs);
    }
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _platform = settings.platform;
      _enableBalance = settings.enableBalance;
      _notConfigured = settings.apiKey.isEmpty;
      if (_balance != null) _loading = false;
    });
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
      children: [
        // 标题栏（保持原造型）
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
              onTap: () => PanelDataService.refreshBalance(),
              child: Icon(Icons.refresh_rounded, color: tertiaryText, size: 20),
            ),
          ],
        ),
        // 内容区域
        Expanded(
          child: _loading
              ? Center(
                  child: Text('检测中...', style: TextStyle(color: mutedText, fontSize: 14)),
                )
              : _notConfigured
                  ? _buildErrorContent('请先配置 API Key')
                  : !_connected
                      ? _buildErrorContent('连接失败，请检查配置')
                      : _enableBalance && _balance != null
                          ? _buildBalanceContent()
                          : _buildEmptyContent(),
        ),
      ],
    );
  }

  Widget _buildErrorContent(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: mutedText, fontSize: 14),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => PanelDataService.refreshBalance(),
            child: Text(
              '点击重试',
              style: TextStyle(color: tertiaryText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyContent() {
    final symbol = _balance?.currency == 'USD' ? '\$' : '¥';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 余额显示
          Text(
            '$symbol 0.00',
            style: TextStyle(
              color: primaryText,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // 柱状图
          Expanded(
            child: _buildBarChart([]),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceContent() {
    final b = _balance!;
    final symbol = b.currency == 'USD' ? '\$' : '¥';
    final accent = isDark ? const Color(0xFF00E5FF) : const Color(0xFF2979FF);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 余额显示
          Text(
            '$symbol${b.totalBalance.toStringAsFixed(2)}',
            style: TextStyle(
              color: primaryText,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '当前余额',
            style: TextStyle(
              color: tertiaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          // 柱状图（使用真实记录数据）
          Expanded(
            child: _buildBarChart(_dailyCosts, accent: accent),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<DailyCost> data, {Color? accent}) {
    final chartColor = accent ?? (isDark ? const Color(0xFF00E5FF) : const Color(0xFF2979FF));
    final gridColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08);

    if (data.isEmpty) {
      return Center(
        child: Text(
          '暂无使用数据',
          style: TextStyle(color: tertiaryText, fontSize: 12),
        ),
      );
    }

    final rawMax = data.map((e) => e.amount).reduce((a, b) => a > b ? a : b);
    final maxY = rawMax > 0 ? rawMax : 1.0; // 避免全为 0 时图表异常

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.2,
        minY: 0,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${data[group.x].day}  ¥${rod.toY.toStringAsFixed(2)}',
                TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < data.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      data[value.toInt()].day,
                      style: TextStyle(
                        color: tertiaryText,
                        fontSize: 11,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: gridColor,
              strokeWidth: 1,
            );
          },
        ),
        barGroups: data.asMap().entries.map((entry) {
          final index = entry.key;
          final usage = entry.value;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: usage.amount,
                color: chartColor,
                width: 16,
                borderRadius: BorderRadius.circular(4),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY * 1.2,
                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
                ),
              ),
            ],
          );
        }).toList(),
      ),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

