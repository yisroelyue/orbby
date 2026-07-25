import 'dart:async';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import '../services/llm_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class NewsPanel extends BasePanel {
  const NewsPanel({super.key});

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends BasePanelState<NewsPanel> {
  bool _panelEnabled = true;
  bool _loading = true;
  bool _isQuerying = false;
  bool _isError = false;
  String _resultText = '';
  Timer? _clearTimer;

  @override
  String get panelTitle => '新闻';

  @override
  PanelIcon get panelIcon => const PanelIcon.icon(Icons.newspaper_rounded);

  @override
  VoidCallback? get onHeaderTap => () {};

  @override
  List<Widget> buildHeaderActions() {
    return [
      InteractiveIcon(
        size: 28,
        onTap: () {
          if (!_isQuerying) _fetchNews();
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
            : Icon(Icons.refresh_rounded, color: tertiaryText, size: 18),
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _fetchSettings();
    MenuScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _fetchSettings();
  }

  void _startClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(minutes: 15), () {
      if (mounted) setState(() => _resultText = '');
    });
  }

  static const _systemPrompt = '你是一个新闻摘要助手。请返回今日最值得关注的 5 条热点新闻。'
      '每条新闻用一行文字概括，格式：\n'
      '1. [标题] 简要内容（一句话）\n'
      '2. ...\n'
      '只输出新闻列表，不要添加其他内容。';

  Future<void> _fetchNews() async {
    _clearTimer?.cancel();
    setState(() => _isQuerying = true);
    try {
      final result = await LlmService.ask(
        '今天有什么重要新闻？',
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
        _resultText = '获取新闻失败: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _isQuerying = false);
    }
  }

  Future<void> _fetchSettings() async {
    setState(() => _loading = true);
    final settings = await SettingsService.load();
    _panelEnabled = settings.showNewsPanel;
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
        _buildQueryButton(),
        _buildResultArea(),
      ],
    );
  }

  Widget _buildQueryButton() {
    if (_resultText.isNotEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isQuerying ? null : _fetchNews,
        icon: _isQuerying
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.newspaper_rounded, size: 16),
        label: Text(_isQuerying ? '获取中...' : '获取今日热点'),
        style: ElevatedButton.styleFrom(
          backgroundColor: hoverBg,
          foregroundColor: primaryText,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
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
                  _isError ? '错误' : '今日热点',
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
