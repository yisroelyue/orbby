import 'dart:async';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import '../services/llm_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class WeatherPanel extends BasePanel {
  const WeatherPanel({super.key});

  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends BasePanelState<WeatherPanel> {
  bool _panelEnabled = true;
  bool _loading = true;
  bool _isQuerying = false;
  bool _isError = false;
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  String _resultText = '';
  Timer? _clearTimer;

  @override
  String get panelTitle => '天气';

  @override
  PanelIcon get panelIcon => const PanelIcon.icon(Icons.cloud_rounded);

  @override
  VoidCallback? get onHeaderTap => () {};

  @override
  void initState() {
    super.initState();
    _fetch();
    MenuScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onRefresh() {
    _fetch();
  }

  void _startClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(minutes: 10), () {
      if (mounted) setState(() => _resultText = '');
    });
  }

  static const _systemPrompt = '你是一个天气查询助手。根据用户输入的城市名，提供简洁的天气信息。'
      '请用以下格式回复（不要添加其他内容）：\n'
      '城市：xxx\n'
      '天气：晴/多云/雨等\n'
      '温度：xx°C ~ xx°C\n'
      '风力：xx级\n'
      '建议：穿衣/出行建议（一句话）';

  Future<void> _queryWeather() async {
    final city = _inputController.text.trim();
    if (city.isEmpty) {
      setState(() {
        _resultText = '请输入城市名称';
        _isError = true;
      });
      return;
    }
    _clearTimer?.cancel();
    setState(() => _isQuerying = true);
    try {
      final result = await LlmService.ask(
        '$city今天天气怎么样？',
        systemPrompt: _systemPrompt,
      );
      if (!mounted) return;
      setState(() {
        _resultText = result;
        _isError = false;
      });
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
        _resultText = '查询失败: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _isQuerying = false);
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final settings = await SettingsService.load();
    _panelEnabled = settings.showWeatherPanel;
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildInputRow(),
        _buildResultArea(),
      ],
    );
  }

  Widget _buildInputRow() {
    return Container(
      decoration: BoxDecoration(
        color: hoverBg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 2, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocus,
              cursorColor: primaryText,
              style: TextStyle(
                color: primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (!_isQuerying) _queryWeather();
              },
              decoration: InputDecoration(
                hintText: '输入城市名称...',
                hintStyle: TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          InteractiveIcon(
            size: 32,
            onTap: () {
              if (_isQuerying) return;
              _queryWeather();
            },
            child: _isQuerying
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tertiaryText,
                    ),
                  )
                : Icon(Icons.cloud_rounded, color: tertiaryText, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArea() {
    if (_resultText.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isError ? '错误' : '天气信息',
                  style: TextStyle(
                    color: _isError ? Colors.redAccent : tertiaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                InteractiveIcon(
                  size: 24,
                  onTap: () => setState(() => _resultText = ''),
                  child: Icon(Icons.close, color: mutedText, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              _resultText,
              style: TextStyle(
                color: _isError ? Colors.redAccent : primaryText,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
