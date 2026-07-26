import 'dart:async';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';
import '../services/llm_service.dart';
import '../services/panel_cache.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class WeatherPanel extends BasePanel {
  const WeatherPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'weather';

  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends BasePanelState<WeatherPanel> {
  bool _loading = true;
  bool _isQuerying = false;
  bool _isError = false;

  String _resultText = '';

  Timer? _clearTimer;

  static const String _systemPrompt =
      '你是一个天气查询助手，请提供上海今天的天气信息。\n'
      '请严格使用以下格式回复，不要使用 Markdown，不要添加其他内容：\n'
      '天气：晴/多云/阴/雨/雪等\n'
      '温度：xx°C ~ xx°C\n'
      '风力：xx级\n'
      '建议：穿衣或出行建议（一句话）';

  @override
  void initState() {
    super.initState();

    // 先从缓存恢复数据
    final cached = PanelCache.get<String>('weather_result');
    if (cached != null && cached.isNotEmpty) {
      _resultText = cached;
      _loading = false;
    }

    HomeScreen.refreshNotifier.addListener(_onRefresh);
    _fetch();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    HomeScreen.refreshNotifier.removeListener(_onRefresh);

    super.dispose();
  }

  void _onRefresh() {
    _fetch();
  }

  void _startClearTimer() {
    _clearTimer?.cancel();

    _clearTimer = Timer(const Duration(minutes: 30), () {
      if (!mounted) return;

      setState(() {
        _resultText = '';
        _isError = false;
      });
    });
  }

  Future<void> _fetch() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      if (_resultText.isEmpty) {
        await _fetchWeather();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _isError = true;
        _resultText = '读取天气面板设置失败：$e';
      });
    }
  }

  Future<void> _fetchWeather() async {
    if (_isQuerying) return;

    _clearTimer?.cancel();

    setState(() {
      _isQuerying = true;
    });

    try {
      final result = await LlmService.ask(
        '上海今天天气怎么样？',
        systemPrompt: _systemPrompt,
        timeout: const Duration(seconds: 20),
      );

      if (!mounted) return;

      setState(() {
        _resultText = result.trim();
        _isError = false;
      });

      PanelCache.set('weather_result', _resultText);
      _startClearTimer();
    } on LlmException catch (e) {
      if (!mounted) return;

      setState(() {
        _resultText = e.message;
        _isError = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _resultText = '天气查询失败：$e';
        _isError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isQuerying = false;
        });
      }
    }
  }

  String _extractValue(String label) {
    for (final originalLine in _resultText.split('\n')) {
      final line = originalLine
          .trim()
          .replaceAll('**', '')
          .replaceFirst(RegExp(r'^[-*]\s*'), '');

      final chinesePrefix = '$label：';
      final englishPrefix = '$label:';

      if (line.startsWith(chinesePrefix)) {
        final value = line.substring(chinesePrefix.length).trim();
        return value.isEmpty ? '--' : value;
      }

      if (line.startsWith(englishPrefix)) {
        final value = line.substring(englishPrefix.length).trim();
        return value.isEmpty ? '--' : value;
      }
    }

    return '--';
  }

  IconData _weatherIcon(String weather) {
    if (weather.contains('雷')) {
      return Icons.thunderstorm_rounded;
    }

    if (weather.contains('雨')) {
      return Icons.water_drop_rounded;
    }

    if (weather.contains('雪')) {
      return Icons.ac_unit_rounded;
    }

    if (weather.contains('阴')) {
      return Icons.cloud_rounded;
    }

    if (weather.contains('多云')) {
      return Icons.cloud_queue_rounded;
    }

    if (weather.contains('雾') || weather.contains('霾')) {
      return Icons.blur_on_rounded;
    }

    return Icons.wb_sunny_rounded;
  }

  Color _weatherColor(String weather) {
    if (weather.contains('雷')) {
      return const Color(0xFF7067CF);
    }

    if (weather.contains('雨')) {
      return const Color(0xFF4C83F3);
    }

    if (weather.contains('雪')) {
      return const Color(0xFF63B7D8);
    }

    if (weather.contains('阴')) {
      return const Color(0xFF758195);
    }

    if (weather.contains('多云')) {
      return const Color(0xFF5F92C9);
    }

    if (weather.contains('雾') || weather.contains('霾')) {
      return const Color(0xFF88929E);
    }

    return const Color(0xFFFFA726);
  }

  @override


  @override
  BoxDecoration? get panelDecoration {
    if (_resultText.isEmpty || _isError) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0A1628), const Color(0xFF0D1F3C)]
              : [const Color(0xFFDCE8F5), const Color(0xFFE8EFF8)],
        ),
      );
    }

    final weather = _extractValue('天气');
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
                Color.lerp(const Color(0xFFDCE8F5), accentColor, 0.2)!,
                Color.lerp(const Color(0xFFE8EFF8), accentColor, 0.05)!,
              ],
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading && _resultText.isEmpty) {
      return _buildLoadingContent();
    }

    if (_isQuerying && _resultText.isEmpty) {
      return _buildLoadingContent();
    }

    if (_resultText.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isError) {
      return _buildErrorContent();
    }

    final weather = _extractValue('天气');
    final temperature = _extractValue('温度');
    final wind = _extractValue('风力');
    final suggestion = _extractValue('建议');
    final accentColor = _weatherColor(weather);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _weatherIcon(weather),
                color: accentColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weather,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '上海 · 今日天气',
                    style: TextStyle(
                      color: tertiaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            InteractiveIcon(
              size: 28,
              onTap: () {
                if (!_isQuerying) {
                  _fetchWeather();
                }
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
        ),
        const SizedBox(height: 16),
        Text(
          temperature,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: primaryText,
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        _buildInfoItem(
          icon: Icons.air_rounded,
          label: '风力',
          value: wind,
        ),
        const SizedBox(height: 14),
        Divider(
          height: 1,
          color: accentColor.withOpacity(0.15),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              color: accentColor,
              size: 18,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                suggestion,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
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
        Icon(
          icon,
          color: tertiaryText,
          size: 17,
        ),
        const SizedBox(width: 6),
        Text(
          '$label  ',
          style: TextStyle(
            color: tertiaryText,
            fontSize: 12,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tertiaryText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '正在获取天气...',
              style: TextStyle(
                color: tertiaryText,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorContent() {
    return GestureDetector(
      onTap: () {
        if (!_isQuerying) _fetchWeather();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hoverBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: tertiaryText,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              '暂时获取不到天气',
              style: TextStyle(
                color: primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点击重试',
              style: TextStyle(
                color: tertiaryText,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}