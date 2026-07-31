import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/news_service.dart';
import '../services/panel_data_service.dart';
import '../services/rss_service.dart';
import 'base_panel.dart';

class NewsPanel extends BasePanel {
  const NewsPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.full;

  @override
  String get panelName => 'news';

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends BasePanelState<NewsPanel> {
  bool _loading = true;

  /// 当前展示的三条新闻
  List<RssNewsItem> _items = [];

  /// 轮换定时器
  Timer? _rotateTimer;

  static const Color _redAccent = Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    super.dispose();
  }

  /// 立刻换下一批
  void _next() {
    NewsCache.instance.next();
    _updateItems();
  }

  Future<void> _init() async {
    if (mounted) setState(() => _loading = true);

    // 初始化缓存（首次会拉取数据）
    await NewsCache.instance.init();

    // 获取当前新闻
    _updateItems();

    // 监听轮换（每 30s 更新一次 UI）
    _rotateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateItems();
    });

    if (mounted) setState(() => _loading = false);
  }

  void _updateItems() {
    final items = NewsCache.instance.currentThree;
    if (items.isEmpty) return;
    if (mounted) {
      setState(() {
        _items = items;
      });
    }
  }

  /// 重新拉取数据
  Future<void> _retry() async {
    if (mounted) setState(() => _loading = true);
    await PanelDataService.refreshNews();
    _updateItems();
    if (mounted) setState(() => _loading = false);
  }

  /// 打开链接
  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return _buildLoading();
    }

    if (_items.isEmpty) {
      return _buildError();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部：标题 + 刷新按钮
        Row(
          children: [
            Expanded(
              child: Text(
                '热点资讯',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: primaryText,
                ),
              ),
            ),
            _RefreshButton(
              loading: _loading,
              tertiaryText: tertiaryText,
              onTap: _next,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 新闻列表
        ..._items.map((item) => _buildNewsItem(item)),
      ],
    );
  }

  Widget _buildNewsItem(RssNewsItem item) {
    return _NewsItemWidget(
      item: item,
      redAccent: _redAccent,
      primaryText: primaryText,
      secondaryText: secondaryText,
      tertiaryText: tertiaryText,
      onOpenUrl: _openUrl,
    );
  }

  // ── Loading / Error ──

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _redAccent),
          ),
          const SizedBox(height: 10),
          Text(
            '正在搜索热点...',
            style: TextStyle(color: tertiaryText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: tertiaryText, size: 28),
          const SizedBox(height: 8),
          Text(
            '新闻获取失败',
            style: TextStyle(
              color: primaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _loading ? null : _retry,
            style: TextButton.styleFrom(
              foregroundColor: _redAccent,
              minimumSize: const Size(96, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: _loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('点击重试'),
          ),
        ],
      ),
    );
  }
}

class _NewsItemWidget extends StatefulWidget {
  final RssNewsItem item;
  final Color redAccent;
  final Color primaryText;
  final Color secondaryText;
  final Color tertiaryText;
  final Future<void> Function(String url) onOpenUrl;

  const _NewsItemWidget({
    required this.item,
    required this.redAccent,
    required this.primaryText,
    required this.secondaryText,
    required this.tertiaryText,
    required this.onOpenUrl,
  });

  @override
  State<_NewsItemWidget> createState() => _NewsItemWidgetState();
}

class _NewsItemWidgetState extends State<_NewsItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题 - 可点击，有 hover 效果
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: () => widget.onOpenUrl(widget.item.url),
              child: Row(
                children: [
                  // 类型标记
                  if (widget.item.category.isNotEmpty) ...[
                    Builder(
                      builder: (context) {
                        final color = Color(NewsCache.categoryColors[widget.item.category] ?? 0xFFE53935);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.item.category,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 标题文本
                  Expanded(
                    child: Text(
                      widget.item.title.isEmpty ? '正在获取新闻...' : widget.item.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _isHovered
                            ? widget.redAccent
                            : (widget.item.title.isEmpty ? widget.tertiaryText : widget.primaryText),
                        height: 1.3,
                        decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
                        decorationColor: widget.redAccent,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 一行正文
          Text(
            widget.item.summary.isEmpty ? '' : widget.item.summary,
            style: TextStyle(
              fontSize: 12,
              color: widget.secondaryText,
              height: 1.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  final bool loading;
  final Color tertiaryText;
  final VoidCallback onTap;

  const _RefreshButton({
    required this.loading,
    required this.tertiaryText,
    required this.onTap,
  });

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: widget.loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.tertiaryText,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: _isHovered
                      ? const Color(0xFFE53935)
                      : widget.tertiaryText,
                  size: 18,
                ),
        ),
      ),
    );
  }
}
