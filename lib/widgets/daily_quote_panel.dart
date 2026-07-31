import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class DailyQuotePanel extends BasePanel {
  const DailyQuotePanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.full;

  @override
  bool get isCarousel => true;

  @override
  String get panelName => 'daily_quote';

  @override
  State<DailyQuotePanel> createState() => _DailyQuotePanelState();
}

class _DailyQuotePanelState extends BasePanelState<DailyQuotePanel>
    with SingleTickerProviderStateMixin {
  @override
  EdgeInsetsGeometry get panelPadding => const EdgeInsets.symmetric(horizontal: 14, vertical: 12);
  bool _isQuerying = false;
  bool _isError = false;

  String _quoteText = '';
  String _quoteAuthor = '';
  String _quoteSource = '';

  Timer? _clearTimer;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // 书籍暖色调
  static const Color _parchment = Color(0xFFF5EFE6);
  static const Color _warmBrown = Color(0xFF8B6914);
  static const Color _deepBrown = Color(0xFF5C4033);
  static const Color _goldAccent = Color(0xFFC9A94E);
  static const Color _bookmarkRed = Color(0xFFB85C38);

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);

    if (!PanelCache.has('daily_quote')) {
      setState(() => _isQuerying = true);
      PanelDataService.refreshDailyQuote();
    }
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _fadeController.dispose();
    PanelCache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<Map<String, String>>('daily_quote');
    if (cached != null && mounted) {
      setState(() {
        _quoteText = cached['text'] ?? '';
        _quoteAuthor = cached['author'] ?? '';
        _quoteSource = cached['source'] ?? '';
        _isQuerying = false;
        _isError = false;
      });
      if (_quoteText.isNotEmpty) _fadeController.forward();
      _startClearTimer();
    }
  }

  void _startClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(minutes: 30), () {
      if (!mounted) return;
      setState(() {
        _quoteText = '';
        _quoteAuthor = '';
        _quoteSource = '';
        _isError = false;
      });
    });
  }

  /// 手动刷新
  void _manualRefresh() {
    if (_isQuerying) return;
    _clearTimer?.cancel();
    _fadeController.reset();
    setState(() => _isQuerying = true);
    PanelDataService.refreshDailyQuote();
  }

  @override


  @override
  BoxDecoration? get panelDecoration {
    if (_quoteText.isEmpty || _isError) return null;

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF2A2520),
                const Color(0xFF1E1B18),
              ]
            : [
                _parchment,
                const Color(0xFFFAF4EB),
              ],
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_isQuerying && _quoteText.isEmpty) {
      return _buildLoadingContent();
    }

    if (_quoteText.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isError) {
      return _buildErrorContent();
    }

    return _buildBookContent();
  }

  Widget _buildBookContent() {
    final textColor = isDark ? Colors.white : _deepBrown;
    final secondaryColor = isDark ? Colors.white60 : _warmBrown;
    final accentColor = isDark ? const Color(0xFFD4A843) : _goldAccent;
    final bookmarkColor = isDark ? const Color(0xFFCF6B51) : _bookmarkRed;
    final quoteMarkColor = isDark
        ? Colors.white.withOpacity(0.08)
        : _warmBrown.withOpacity(0.08);
    final dividerColor = isDark
        ? Colors.white.withOpacity(0.1)
        : _warmBrown.withOpacity(0.12);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 右上角书签丝带
        Positioned(
          top: -6,
          right: 36,
          child: SvgPicture.asset(
            'assets/svg/bookmark.svg',
            width: 20,
            height: 34,
            colorFilter: ColorFilter.mode(bookmarkColor, BlendMode.srcIn),
          ),
        ),

        // 装饰性大引号
        Positioned(
          top: 2,
          left: 2,
          child: Text(
            '“',
            style: TextStyle(
              fontSize: 44,
              height: 1,
              fontWeight: FontWeight.bold,
              color: quoteMarkColor,
            ),
          ),
        ),

        // 主内容
        FadeTransition(
          opacity: _fadeAnimation,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // 顶部标签行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_rounded,
                          size: 13,
                          color: accentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '每日一言',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InteractiveIcon(
                    size: 28,
                    onTap: () {
                      if (!_isQuerying) {
                        _quoteText = '';
                        _quoteAuthor = '';
                        _quoteSource = '';
                        _manualRefresh();
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

              const SizedBox(height: 12),

              // 引言正文
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 16),
                child: Text(
                  _quoteText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // 分割线
              Container(
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

              const SizedBox(height: 8),

              // 作者 & 来源
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 作者头像（首字母）
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withOpacity(0.15),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _quoteAuthor.isNotEmpty
                          ? _quoteAuthor.characters.first
                          : '?',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_quoteAuthor.isNotEmpty)
                          Text(
                            _quoteAuthor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: secondaryColor,
                            ),
                          ),
                        if (_quoteSource.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                              top: _quoteAuthor.isNotEmpty ? 1 : 0,
                            ),
                            child: Text(
                              '—— $_quoteSource',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: secondaryColor.withOpacity(0.6),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
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
              '正在翻阅...',
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
    final accentColor = isDark ? const Color(0xFFD4A843) : _goldAccent;

    return GestureDetector(
      onTap: () {
        if (!_isQuerying) _manualRefresh();
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
              Icons.auto_stories_rounded,
              color: tertiaryText,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              '暂时翻不到好句',
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
                color: accentColor,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
