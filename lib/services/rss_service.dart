import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class RssNewsItem {
  final String title;
  final String summary;
  final String url;
  final String source;
  final String imageUrl;
  final DateTime? publishedAt;
  final String category;

  const RssNewsItem({
    required this.title,
    required this.summary,
    required this.url,
    required this.source,
    this.imageUrl = '',
    this.publishedAt,
    this.category = '',
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'summary': summary,
    'url': url,
    'source': source,
    'imageUrl': imageUrl,
    'time': publishedAt?.toIso8601String() ?? '',
  };
}

class RssService {
  RssService._();

  static final Map<String, ({DateTime expires, List<RssNewsItem> items})>
  _cache = {};

  static Future<List<RssNewsItem>> search(
    List<String> feeds, {
    String query = '',
    int limit = 10,
  }) async {
    final all = <RssNewsItem>[];
    for (final feed in feeds.where((url) => url.trim().isNotEmpty)) {
      try {
        final items = await _fetch(feed.trim());
        all.addAll(items);
      } catch (error, stackTrace) {}
    }
    final keyword = query.trim().toLowerCase();
    final result =
        all
            .where(
              (item) =>
                  keyword.isEmpty ||
                  '${item.title} ${item.summary}'.toLowerCase().contains(
                    keyword,
                  ),
            )
            .toList()
          ..sort(
            (a, b) => (b.publishedAt ?? DateTime(1970)).compareTo(
              a.publishedAt ?? DateTime(1970),
            ),
          );
    final seen = <String>{};
    return result
        .where((item) => seen.add(item.url.isEmpty ? item.title : item.url))
        .take(limit.clamp(1, 30))
        .toList();
  }

  static Future<List<RssNewsItem>> _fetch(String url) async {
    final cached = _cache[url];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.items;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'Orbby/1.0 RSS Reader');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );

      if (response.statusCode != 200)
        throw HttpException('RSS ${response.statusCode}');
      final body = await response.transform(utf8.decoder).join();
      if (body.length > 2 * 1024 * 1024)
        throw const FormatException('RSS response too large');
      final items = _parse(body, Uri.parse(url).host);

      _cache[url] = (
        expires: DateTime.now().add(const Duration(minutes: 5)),
        items: items,
      );
      return items;
    } finally {
      client.close(force: true);
    }
  }

  static List<RssNewsItem> _parse(String xml, String source) {
    final blocks = RegExp(
      r'<item\b[^>]*>(.*?)</item\s*>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(xml).map((m) => m.group(1)!).toList();
    return blocks
        .map((entry) {
          final imageUrl = _extractImageUrl(entry);
          if (imageUrl.isNotEmpty) {}
          return RssNewsItem(
            title: _decode(_tag(entry, 'title')),
            summary: _stripHtml(_decode(_tag(entry, 'description'))),
            url: _tag(entry, 'link').trim(),
            source: source,
            imageUrl: imageUrl,
            publishedAt: DateTime.tryParse(_tag(entry, 'pubDate')),
          );
        })
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();
  }

  /// 从 RSS item 中提取图片 URL
  /// 优先级：enclosure(type=image) > media:content > description 中的 img
  static String _extractImageUrl(String entry) {
    // 1. enclosure 标签（type 为 image/ 开头）
    final enclosureMatch = RegExp(
      r'<enclosure\b[^>]*type="image/[^"]*"[^>]*url="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(entry);
    if (enclosureMatch != null) return enclosureMatch.group(1)!;

    // 也支持 url 在 type 前面的情况
    final enclosureMatch2 = RegExp(
      r'<enclosure\b[^>]*url="([^"]+)"[^>]*type="image/[^"]*"',
      caseSensitive: false,
    ).firstMatch(entry);
    if (enclosureMatch2 != null) return enclosureMatch2.group(1)!;

    // 2. media:content 标签
    final mediaMatch = RegExp(
      r'<media:content\b[^>]*url="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(entry);
    if (mediaMatch != null) return mediaMatch.group(1)!;

    // 3. media:thumbnail 标签
    final thumbnailMatch = RegExp(
      r'<media:thumbnail\b[^>]*url="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(entry);
    if (thumbnailMatch != null) return thumbnailMatch.group(1)!;

    // 4. description 中的 img 标签
    final description = _tag(entry, 'description');
    final imgMatch = RegExp(
      r'<img\b[^>]*src="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(description);
    if (imgMatch != null) return _decode(imgMatch.group(1)!);

    return '';
  }

  static String _tag(String xml, String tag) =>
      RegExp(
        '<$tag[^>]*>(.*?)</$tag\\s*>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(xml)?.group(1)?.trim() ??
      '';

  static String _stripHtml(String value) => value
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _decode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
