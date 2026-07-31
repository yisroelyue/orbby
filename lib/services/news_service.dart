import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'rss_service.dart';

/// 新闻缓存管理
/// - 启动时拉取，存到内存
/// - 每 30s 轮换展示三条随机新闻
/// - 每天 9 点重新拉取
class NewsCache {
  NewsCache._();

  static final NewsCache instance = NewsCache._();

  /// 写死的 RSS 源（url -> 类型标记）
  static const feeds = [
    ('https://www.chinanews.com.cn/rss/scroll-news.xml', '要闻'),
    ('https://www.chinanews.com.cn/rss/importnews.xml', '时政'),
    ('https://www.chinanews.com.cn/rss/china.xml', '国内'),
    ('https://www.chinanews.com.cn/rss/dxw.xml', '国际'),
    ('https://www.chinanews.com.cn/rss/world.xml', '社会'),
    ('https://www.chinanews.com.cn/rss/society.xml', '财经'),
    ('https://www.chinanews.com.cn/rss/finance.xml', '生活'),
    ('https://www.chinanews.com.cn/rss/life.xml', '健康'),
    ('https://www.chinanews.com.cn/rss/jk.xml', '大湾区'),
    ('https://www.chinanews.com.cn/rss/dwq.xml', '华人'),
    ('https://www.chinanews.com.cn/rss/chinese.xml', '文娱'),
    ('https://www.chinanews.com.cn/rss/culture.xml', '体育'),
    ('https://www.chinanews.com.cn/rss/sports.xml', '视频'),
    ('https://www.chinanews.com.cn/rss/sp.xml', '图片'),
    ('https://www.chinanews.com.cn/rss/photo.xml', '创意'),
    ('https://www.chinanews.com.cn/rss/chuangyi.xml', '直播'),
    ('https://www.chinanews.com.cn/rss/zhibo.xml', '教育'),
    ('https://www.chinanews.com.cn/rss/edu.xml', '法治'),
    ('https://www.chinanews.com.cn/rss/fz.xml', '法治'),
  ];

  /// 类型颜色映射
  static const categoryColors = {
    '要闻': 0xFFE53935, // 红
    '时政': 0xFF1E88E5, // 蓝
    '国内': 0xFF43A047, // 绿
    '国际': 0xFFFF8F00, // 橙
    '社会': 0xFF8E24AA, // 紫
    '财经': 0xFF00ACC1, // 青
    '生活': 0xFFEC407A, // 粉
    '健康': 0xFF66BB6A, // 浅绿
    '大湾区': 0xFF5C6BC0, // 靛蓝
    '华人': 0xFF26A69A, // 蓝绿
    '文娱': 0xFFAB47BC, // 浅紫
    '体育': 0xFFFF7043, // 深橙
    '视频': 0xFFEF5350, // 浅红
    '图片': 0xFF42A5F5, // 浅蓝
    '创意': 0xFF9CCC65, // 橙绿
    '直播': 0xFFEEFF41, // 黄
    '教育': 0xFF7E57C2, // 深紫
    '法治': 0xFF78909C, // 灰蓝
  };

  /// 每个源拉取的条数
  static const _perFeedLimit = 3;

  /// 缓存的新闻列表
  List<RssNewsItem> _pool = [];

  /// 当前展示的索引
  int _currentIndex = 0;

  /// 轮换定时器
  Timer? _rotateTimer;

  /// 每日刷新定时器
  Timer? _dailyTimer;

  /// 是否已初始化
  bool _initialized = false;

  /// 初始化：拉取数据 + 启动定时器
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _fetch();

    // 每 30s 轮换
    _rotateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _rotate();
    });

    // 每天 9 点重新拉取
    _scheduleDailyFetch();

    debugPrint('[News] 初始化完成，共 ${_pool.length} 条新闻');
  }

  /// 获取当前展示的新闻
  RssNewsItem? get current {
    if (_pool.isEmpty) return null;
    return _pool[_currentIndex % _pool.length];
  }

  /// 获取随机三条新闻
  List<RssNewsItem> get currentThree {
    if (_pool.isEmpty) return [];
    if (_pool.length <= 3) return List.from(_pool);
    final random = Random();
    final indices = <int>{};
    while (indices.length < 3) {
      indices.add(random.nextInt(_pool.length));
    }
    return indices.map((i) => _pool[i]).toList();
  }

  /// 立刻切换到下一条
  void next() {
    if (_pool.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _pool.length;
    debugPrint(' ${_pool[_currentIndex + 1]} ');
  }

  /// 重新拉取全部数据
  Future<void> refresh() async {
    await _fetch();
  }

  /// 从各 RSS 源并发拉取新闻
  Future<void> _fetch() async {
    // 并发拉取，每个源独立，一个超时不影响其他
    final results = await Future.wait(
      feeds.map((feed) async {
        try {
          final items = await RssService.search([feed.$1], limit: _perFeedLimit);
          // 为每条新闻添加类型标记
          return items.map((item) => RssNewsItem(
            title: item.title,
            summary: item.summary,
            url: item.url,
            source: item.source,
            imageUrl: item.imageUrl,
            publishedAt: item.publishedAt,
            category: feed.$2,
          )).toList();
        } catch (e) {
          return <RssNewsItem>[];
        }
      }),
    );

    final all = results.expand((list) => list).toList();

    if (all.isNotEmpty) {
      _pool = all;
      _currentIndex = 0;
    } else {}
  }

  /// 轮换到下一条
  void _rotate() {
    if (_pool.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _pool.length;
  }

  /// 安排每天 9 点的定时拉取
  void _scheduleDailyFetch() {
    _dailyTimer?.cancel();

    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, 9, 0);
    if (now.isAfter(next)) {
      next = next.add(const Duration(days: 1));
    }

    final delay = next.difference(now);

    _dailyTimer = Timer(delay, () {
      _fetch();
      // 拉取完成后安排下一天
      _scheduleDailyFetch();
    });
  }

  /// 销毁（测试用）
  void dispose() {
    _rotateTimer?.cancel();
    _dailyTimer?.cancel();
    _initialized = false;
  }
}
