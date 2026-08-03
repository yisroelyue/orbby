import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import '../services/weather_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class WeatherPanel extends BasePanel {
  const WeatherPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.full;

  @override
  bool get isCarousel => true;

  @override
  String get panelName => 'weather';

  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends BasePanelState<WeatherPanel> {
  bool _loading = true;
  bool _isQuerying = false;
  bool _isError = false;
  String _errorMessage = '';

  /// 天气数据
  WeatherData? _data;

  Timer? _dailyTimer;

  static const Color _cyan = Color(0xFF00E5FF);
  static const Color _electricBlue = Color(0xFF2979FF);

  @override
  void initState() {
    super.initState();

    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);
    _checkAndFetch();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<String>('weather_result');
    if (cached != null && cached.isNotEmpty && mounted) {
      try {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        setState(() {
          _data = WeatherData.fromJson(json);
          _loading = false;
          _isError = false;
          _isQuerying = false;
        });
      } catch (_) {}
    }
  }

  /// 检查是否需要获取天气（每天只获取一次）
  Future<void> _checkAndFetch() async {
    final settings = await SettingsService.load();
    final today = DateTime.now().toString().substring(0, 10);

    if (settings.weatherLastFetchDate == today && _data != null) {
      _scheduleNextUpdate();
      return;
    }

    // 没有今天的缓存，触发刷新
    setState(() => _loading = true);
    PanelDataService.refreshWeather();
  }

  @override
  void dispose() {
    _dailyTimer?.cancel();
    PanelCache.removeListener(_onCacheChanged);
    super.dispose();
  }

  /// 手动刷新（点击刷新按钮）
  void _manualRefresh() {
    
    setState(() {
      _isQuerying = true;
      _loading = true;
      _errorMessage = '';
    });
    PanelDataService.refreshWeather();
  }

  /// 计算距离下一个9点的时间
  Duration _timeUntilNext9AM() {
    final now = DateTime.now();
    var next9AM = DateTime(now.year, now.month, now.day, 9);
    if (now.isAfter(next9AM)) {
      next9AM = next9AM.add(const Duration(days: 1));
    }
    return next9AM.difference(now);
  }

  /// 调度下一次9点更新
  void _scheduleNextUpdate() {
    _dailyTimer?.cancel();
    final duration = _timeUntilNext9AM();
    
    _dailyTimer = Timer(duration, () {
      if (!mounted) return;
      PanelDataService.refreshWeather();
    });
  }

  String _field(String key) {
    if (_data == null) return '--';
    switch (key) {
      case 'location':
        return _data!.location.isNotEmpty ? _data!.location : '--';
      case 'weather':
        return _data!.weather;
      case 'temperature':
        return _data!.temperature;
      case 'wind':
        return _data!.wind;
      case 'suggestion':
        return _data!.suggestion;
      default:
        return '--';
    }
  }

  IconData _weatherIcon(String weather) {
    if (weather == '--') return Icons.cloud_queue_rounded;
    if (weather.contains('雷')) return Icons.thunderstorm_rounded;
    if (weather.contains('雨')) return Icons.water_drop_rounded;
    if (weather.contains('雪')) return Icons.ac_unit_rounded;
    if (weather.contains('阴')) return Icons.cloud_rounded;
    if (weather.contains('多云')) return Icons.cloud_queue_rounded;
    if (weather.contains('雾') || weather.contains('霾')) return Icons.blur_on_rounded;
    return Icons.wb_sunny_rounded;
  }

  Color _weatherColor(String weather) {
    if (weather == '--') return tertiaryText;
    if (weather.contains('雷')) return const Color(0xFF7067CF);
    if (weather.contains('雨')) return const Color(0xFF4C83F3);
    if (weather.contains('雪')) return const Color(0xFF63B7D8);
    if (weather.contains('阴')) return const Color(0xFF758195);
    if (weather.contains('多云')) return const Color(0xFF5F92C9);
    if (weather.contains('雾') || weather.contains('霾')) return const Color(0xFF88929E);
    return const Color(0xFFFFA726);
  }

  @override
  BoxDecoration? get panelDecoration {
    final weather = _field('weather');
    final accentColor = _weatherColor(weather);

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                Color.lerp(const Color(0xFF0A1628), accentColor, 0.25)!,
                Color.lerp(const Color(0xFF0D1F3C), accentColor, 0.08)!,
              ]
            : [
                Color.lerp(const Color(0xFFC8DAE8), accentColor, 0.35)!,
                Color.lerp(const Color(0xFFD8E4F0), accentColor, 0.15)!,
              ],
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    final location = _field('location');
    final weather = _field('weather');
    final temperature = _field('temperature');
    final wind = _field('wind');
    final suggestion = _field('suggestion');
    final accentColor = _weatherColor(weather);
    final isLoading = (_loading || _isQuerying) && _data == null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：天气图标
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentColor,
                  ),
                )
              : Icon(
                  _weatherIcon(weather),
                  color: accentColor,
                  size: 32,
                ),
        ),
        const SizedBox(width: 14),
        // 中间：主要信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 天气状况 + 温度 + 地区
              Row(
                children: [
                  Text(
                    weather,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _data == null ? tertiaryText : primaryText,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    temperature,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _data == null ? tertiaryText : primaryText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (location != '--') ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: primaryText,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // 风力信息
              _buildInfoItem(
                icon: Icons.air_rounded,
                label: '风力',
                value: wind,
              ),
              const SizedBox(height: 8),
              // 建议
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: accentColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _isError
                        ? GestureDetector(
                            onTap: () {
                              if (!_isQuerying) _manualRefresh();
                            },
                            child: Text(
                              _errorMessage.isNotEmpty ? _errorMessage : '获取失败，点击重试',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _electricBlue,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          )
                        : Text(
                            suggestion,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _data == null ? tertiaryText : primaryText,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 右侧：刷新按钮
        InteractiveIcon(
          size: 28,
          onTap: () {
            
            if (!_isQuerying) _manualRefresh();
          },
          child: _isQuerying
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tertiaryText,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: tertiaryText,
                  size: 18,
                ),
        ),
      ],
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: tertiaryText, size: 17),
        const SizedBox(width: 6),
        Text(
          '$label  ',
          style: TextStyle(color: tertiaryText, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _data == null ? tertiaryText : primaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
