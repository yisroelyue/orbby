import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import '../config/settings.dart';

class AgentService {
  AgentService._();

  /// 发送消息到 AI，返回回复文本
  static Future<String> chat(
    String userText, {
    String mode = 'accept',
    List<Map<String, String>> history = const [],
  }) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      throw AgentException('消息为空');
    }

    final settings = await SettingsService.load();
    if (settings.apiKey.isEmpty) {
      throw AgentException('请先在设置中配置 API Key');
    }

    final chatUrl = settings.chatUrl.isEmpty
        ? PlatformConfig.defaultChatUrl(settings.platform)
        : settings.chatUrl.trim();

    final model = settings.model.isEmpty
        ? PlatformConfig.defaultChatModel(settings.platform)
        : settings.model;

    debugPrint('━━━ Agent 请求 ━━━');
    debugPrint('平台: ${settings.platform}  模型: $model  模式: $mode');

    final systemPrompt = _systemPrompt(mode);

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...history,
      {'role': 'user', 'content': trimmed},
    ];

    if (PlatformConfig.isAnthropicPlatform(settings.platform)) {
      return _callAnthropic(
        chatUrl, model, settings.apiKey, systemPrompt, messages,
      );
    }
    return _callCompatible(
      chatUrl, model, settings.apiKey, messages,
    );
  }

  static String _systemPrompt(String mode) {
    switch (mode) {
      case 'plan':
        return '你是一个注重规划和结构的助手。回答问题时，先分析需求，'
            '然后提供分步骤的解决方案。回答要结构清晰，条理分明。';
      case 'auto':
        return '你是一个全能助手，根据问题类型自动选择最合适的回答方式。'
            '简洁问题直接回答，复杂问题结构化分析。尽量简洁高效。';
      case 'accept':
      default:
        return '你是 AI 助手。名字叫做 Orbby 助手。是能够帮助用户处理日常任务的电脑助手';
    }
  }

  /// OpenAI 兼容 API
  static Future<String> _callCompatible(
    String url,
    String model,
    String apiKey,
    List<Map<String, String>> messages,
  ) async {
    final uri = Uri.parse(url);
    final body = jsonEncode({
      'model': model,
      'messages': messages,
    });

    debugPrint('━━━ 请求体 ━━━');
    debugPrint(const JsonEncoder.withIndent('  ').convert(jsonDecode(body)));

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $apiKey');
      final bytes = utf8.encode(body);
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close().timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw AgentException('请求超时'),
          );

      final raw = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('━━━ 响应 [${response.statusCode}] ━━━');
        debugPrint(raw);
        throw AgentException('请求失败: HTTP ${response.statusCode}');
      }

      debugPrint('━━━ 响应体 ━━━');
      debugPrint(raw);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw AgentException('AI 返回为空');
      }
      final content = choices.first['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw AgentException('AI 返回为空');
      }
      return content.trim();
    } catch (e) {
      if (e is AgentException) rethrow;
      debugPrint('Agent 异常: $e');
      throw AgentException('请求失败: $e');
    } finally {
      client.close();
    }
  }

  /// Anthropic API
  static Future<String> _callAnthropic(
    String url,
    String model,
    String apiKey,
    String systemPrompt,
    List<Map<String, String>> messages,
  ) async {
    final uri = Uri.parse(url);
    // Anthropic 格式：system 放在顶层，messages 不包含 system
    final userMessages = messages
        .where((m) => m['role'] != 'system')
        .map((m) => {'role': m['role'], 'content': m['content']})
        .toList();

    final body = jsonEncode({
      'model': model,
      'max_tokens': 4096,
      'system': systemPrompt,
      'messages': userMessages,
    });

    debugPrint('━━━ 请求体 ━━━');
    debugPrint(const JsonEncoder.withIndent('  ').convert(jsonDecode(body)));

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('x-api-key', apiKey);
      request.headers.set('anthropic-version', '2023-06-01');
      final bytes = utf8.encode(body);
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close().timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw AgentException('请求超时'),
          );

      final raw = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('━━━ 响应 [${response.statusCode}] ━━━');
        debugPrint(raw);
        throw AgentException('请求失败: HTTP ${response.statusCode}');
      }

      debugPrint('━━━ 响应体 ━━━');
      debugPrint(raw);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final contentList = json['content'] as List<dynamic>?;
      if (contentList == null || contentList.isEmpty) {
        throw AgentException('AI 返回为空');
      }
      final text = contentList.first['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw AgentException('AI 返回为空');
      }
      return text.trim();
    } catch (e) {
      if (e is AgentException) rethrow;
      debugPrint('Anthropic Agent 异常: $e');
      throw AgentException('请求失败: $e');
    } finally {
      client.close();
    }
  }
}

class AgentException implements Exception {
  AgentException(this.message);
  final String message;

  @override
  String toString() => message;
}
