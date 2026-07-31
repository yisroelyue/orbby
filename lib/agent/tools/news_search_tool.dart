import 'dart:convert';

import '../../services/news_service.dart';
import '../../services/rss_service.dart';
import '../types.dart';

final newsSearchTool = ToolDefinition(
  name: 'news_search',
  description: '从 RSS 聚合网站获取实时新闻，返回标题、摘要、来源、时间和链接。',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': '新闻关键词，可为空'},
      'limit': {'type': 'integer', 'description': '最多返回条数，默认 8'},
    },
    'required': ['query'],
  },
  execute: (args) async {
    final items = await RssService.search(
      NewsCache.feeds.map((f) => f.$1).toList(),
      query: args['query'] as String? ?? '',
      limit: (args['limit'] as num?)?.toInt() ?? 8,
    );
    return jsonEncode({
      'type': 'news',
      'updated_at': DateTime.now().toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    });
  },
);
