import 'dart:async';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import '../services/llm_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class DailyQuotePanel extends BasePanel {
  const DailyQuotePanel({super.key});

  @override
  State<DailyQuotePanel> createState() => _DailyQuotePanelState();
}

class _DailyQuotePanelState extends BasePanelState<DailyQuotePanel> {
  bool _panelEnabled = true;
  bool _loading = true;
  bool _isQuerying = false;
  String _quoteText = '';
  String _quoteAuthor = '';

  @override
  String get panelTitle => '每日一言';

  @override
  PanelIcon get panelIcon => const PanelIcon.icon(Icons.format_quote_rounded);

  @override
  VoidCallback? get onHeaderTap => null;

  @override
  List<Widget> buildHeaderActions() {
    return [
      InteractiveIcon(
        size: 28,
        onTap: () {
          if (!_isQuerying) _fetchQuote();
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
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _fetchSettings();
  }

  static const _systemPrompt = '你是一个名言金句推荐助手。请返回一条适合今天阅读的名言、诗句或哲理短句。'
      '可以是古今中外的经典名句、诗词、电影台词等。\n'
      '格式要求（严格遵守，不要添加其他内容）：\n'
      '第一行：名言内容\n'
      '第二行：—— 作者/出处';

  Future<void> _fetchQuote() async {
    setState(() => _isQuerying = true);
    try {
      final result = await LlmService.ask(
        '给我推荐一条今天的名言',
        systemPrompt: _systemPrompt,
      );
      if (!mounted) return;
      final lines = result.split('\n').where((l) => l.trim().isNotEmpty).toList();
      setState(() {
        _quoteText = lines.isNotEmpty ? lines.first.trim() : result;
        _quoteAuthor = lines.length > 1 ? lines.sublist(1).join(' ').trim() : '';
        _isQuerying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteText = '获取失败，请稍后再试';
        _quoteAuthor = '';
        _isQuerying = false;
      });
    }
  }

  Future<void> _fetchSettings() async {
    setState(() => _loading = true);
    final settings = await SettingsService.load();
    _panelEnabled = settings.showDailyQuotePanel;
    if (!mounted) return;
    setState(() => _loading = false);
    // 首次加载自动获取
    if (_panelEnabled && _quoteText.isEmpty) {
      _fetchQuote();
    }
  }

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  Widget buildContent(BuildContext context) {
    if (_quoteText.isEmpty && !_isQuerying) {
      return const SizedBox.shrink();
    }
    if (_isQuerying && _quoteText.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: tertiaryText),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _quoteText,
            style: TextStyle(
              color: primaryText,
              fontSize: 13,
              height: 1.6,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (_quoteAuthor.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _quoteAuthor,
                style: TextStyle(
                  color: tertiaryText,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
