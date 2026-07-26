import 'dart:async';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';
import '../services/llm_service.dart';
import '../services/panel_cache.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class NewsPanel extends BasePanel {
  const NewsPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'news';

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends BasePanelState<NewsPanel>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _isQuerying = false;
  bool _isError = false;
  String _resultText = '';
  Timer? _clearTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // 科技感色调
  static const Color _cyan = Color(0xFF00E5FF);
  static const Color _electricBlue = Color(0xFF2979FF);
  static const Color _deepNavy = Color(0xFF0A1628);
  static const Color _darkPanel = Color(0xFF0D1F3C);
  static const Color _gridLine = Color(0xFF1A3A5C);
  static const Color _neonGreen = Color(0xFF00E676);
  static const Color _softWhite = Color(0xFFE0E6ED);

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 先从缓存恢复数据
    final cached = PanelCache.get<String>('news_result');
    if (cached != null && cached.isNotEmpty) {
      _resultText = cached;
      _loading = false;
    }

    _fetchSettings();
    HomeScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _pulseController.dispose();
    HomeScreen.refreshNotifier.removeListener(_onRefresh);
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

  static const _systemPrompt = '你是一个国内新闻摘要助手。请返回今日最值得关注的 5 条国内热点新闻。'
      '每条新闻用一行文字概括，格式：\n'
      '1. [标题] 简要内容（一句话）\n'
      '2. ...\n'
      '只输出新闻列表，不要添加其他内容。不要输出国际新闻。';

  Future<void> _fetchNews() async {
    _clearTimer?.cancel();
    setState(() => _isQuerying = true);
    try {
      final result = await LlmService.ask(
        '今天国内有什么重要新闻？只关注中国国内热点。',
        systemPrompt: _systemPrompt,
        timeout: const Duration(seconds: 25),
      );
      if (!mounted) return;
      setState(() {
        _resultText = result;
        _isError = false;
      });
      PanelCache.set('news_result', _resultText);
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
    setState(() => _loading = false);
    if (_resultText.isEmpty) _fetchNews();
  }

  /// 解析新闻列表
  List<_NewsItem> _parseNews(String text) {
    final items = <_NewsItem>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 匹配 "1. [标题] 内容" 或 "1. 标题 - 内容" 或 "1. 内容"
      final match = RegExp(r'^(\d+)[.\s、]+(.+)$').firstMatch(trimmed);
      if (match != null) {
        final content = match.group(2)!.trim();
        // 尝试拆分 [标题] 和摘要
        final bracketMatch = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(content);
        if (bracketMatch != null) {
          items.add(_NewsItem(
            title: bracketMatch.group(1)!.trim(),
            summary: bracketMatch.group(2)!.trim(),
          ));
        } else {
          // 尝试拆分 "标题：摘要" 或 "标题 —— 摘要" 或整行作为标题
          final colonSplit = RegExp(r'^(.{2,20})[：:—–-]\s*(.+)$').firstMatch(content);
          if (colonSplit != null) {
            items.add(_NewsItem(
              title: colonSplit.group(1)!.trim(),
              summary: colonSplit.group(2)!.trim(),
            ));
          } else {
            items.add(_NewsItem(title: content, summary: ''));
          }
        }
      }
    }
    return items;
  }

  @override


  @override
  BoxDecoration? get panelDecoration {
    if (_resultText.isEmpty || _isError) return null;

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [_deepNavy, _darkPanel]
            : [
                const Color(0xFFEAF2FB),
                const Color(0xFFF0F4FA),
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

    return _buildTechContent();
  }

  Widget _buildTechContent() {
    final newsItems = _parseNews(_resultText);
    final accent = isDark ? _cyan : _electricBlue;
    final glowColor = isDark ? _cyan.withOpacity(0.15) : _electricBlue.withOpacity(0.08);
    final borderColor = isDark ? _cyan.withOpacity(0.2) : _electricBlue.withOpacity(0.15);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A237E);
    final summaryColor = isDark ? Colors.white60 : const Color(0xFF546E7A);
    final indexBg = isDark ? _cyan.withOpacity(0.12) : _electricBlue.withOpacity(0.1);
    final dividerColor = isDark ? _gridLine : _electricBlue.withOpacity(0.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部 HUD 标题栏
        Row(
          children: [
            // 脉冲指示灯
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _neonGreen.withOpacity(_pulseAnimation.value),
                    boxShadow: [
                      BoxShadow(
                        color: _neonGreen.withOpacity(_pulseAnimation.value * 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _neonGreen,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '热点资讯',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                  letterSpacing: 1,
                ),
              ),
            ),
            // 时间戳
            Text(
              _formatTimestamp(),
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white30 : Colors.black26,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
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
                        color: accent,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, color: tertiaryText, size: 18),
            ),
          ],
        ),

        // 扫描线装饰
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 14),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  accent.withOpacity(0.4),
                  accent.withOpacity(0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.8, 1.0],
              ),
            ),
          ),
        ),

        // 新闻列表
        Expanded(
          child: newsItems.isEmpty
              ? SingleChildScrollView(
                  child: SelectableText(
                    _resultText,
                    style: TextStyle(
                      color: isDark ? _softWhite : const Color(0xFF37474F),
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: newsItems.length,
                  separatorBuilder: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            dividerColor,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final item = newsItems[index];
                    return _buildNewsCard(
                      index: index,
                      item: item,
                      accent: accent,
                      glowColor: glowColor,
                      borderColor: borderColor,
                      titleColor: titleColor,
                      summaryColor: summaryColor,
                      indexBg: indexBg,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNewsCard({
    required int index,
    required _NewsItem item,
    required Color accent,
    required Color glowColor,
    required Color borderColor,
    required Color titleColor,
    required Color summaryColor,
    required Color indexBg,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: glowColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 序号标签
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: indexBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: accent.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 新闻内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  Widget _buildLoadingContent() {
    final accent = isDark ? _cyan : _electricBlue;

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
                color: accent,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '正在获取资讯...',
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
    final accent = isDark ? _cyan : _electricBlue;

    return GestureDetector(
      onTap: () {
        if (!_isQuerying) _fetchNews();
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
              Icons.wifi_off_rounded,
              color: tertiaryText,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              '暂时获取不到资讯',
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
                color: accent,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsItem {
  final String title;
  final String summary;

  const _NewsItem({required this.title, required this.summary});
}
