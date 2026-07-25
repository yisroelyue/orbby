import 'dart:async';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import '../services/llm_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class SchedulePanel extends BasePanel {
  const SchedulePanel({super.key});

  @override
  State<SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends BasePanelState<SchedulePanel> {
  bool _panelEnabled = true;
  bool _loading = true;
  bool _isQuerying = false;
  bool _isError = false;
  String _resultText = '';
  Timer? _clearTimer;

  @override
  String get panelTitle => '日程';

  @override
  PanelIcon get panelIcon => const PanelIcon.icon(Icons.calendar_today_rounded);

  @override
  VoidCallback? get onHeaderTap => null;

  @override
  List<Widget> buildHeaderActions() {
    return [
      InteractiveIcon(
        size: 28,
        onTap: () {
          if (!_isQuerying) _fetchSchedule();
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
    _clearTimer = Timer(const Duration(minutes: 30), () {
      if (mounted) setState(() => _resultText = '');
    });
  }

  static const _systemPrompt = '你是一个日程助手。今天是{date}。请根据用户输入的内容，整理成清晰的日程安排格式。'
      '格式要求：\n'
      '- 按时间顺序排列\n'
      '- 每条一行：时间 事项\n'
      '- 如果没有具体时间，放在末尾\n'
      '- 简洁明了，不要多余文字';

  Future<void> _fetchSchedule() async {
    _clearTimer?.cancel();
    setState(() => _isQuerying = true);
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}年${now.month}月${now.day}日';
      final result = await LlmService.ask(
        '帮我整理今天的日程安排',
        systemPrompt: _systemPrompt.replaceAll('{date}', dateStr),
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

  Future<void> _fetchSettings() async {
    setState(() => _loading = true);
    final settings = await SettingsService.load();
    _panelEnabled = settings.showSchedulePanel;
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
        onPressed: _isQuerying ? null : _fetchSchedule,
        icon: _isQuerying
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome_rounded, size: 16),
        label: Text(_isQuerying ? '生成中...' : '生成今日日程'),
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
                  _isError ? '错误' : '今日日程',
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
