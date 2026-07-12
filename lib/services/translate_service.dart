import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import '../config/settings.dart';

class TranslateService {
  TranslateService._();

  /// 中英互译入口：自动检测语言 → 调用 AI API → 返回翻译结果
  static Future<String> translate(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw TranslateException('请输入要翻译的文本');
    }

    final settings = await SettingsService.load();

    if (settings.apiKey.isEmpty) {
      throw TranslateException('请先在设置中配置 API Key');
    }

    final chatUrl = settings.chatUrl.isEmpty
        ? PlatformConfig.defaultChatUrl(settings.platform)
        : settings.chatUrl.trim();

    final model = settings.model.isEmpty
        ? PlatformConfig.defaultChatModel(settings.platform)
        : settings.model;
    debugPrint('━━━ 翻译请求 ━━━');
    debugPrint('平台: ${settings.platform}  模型: $model');
    debugPrint('URL: $chatUrl');
    final toEnglish = _isChinese(trimmed);
    final systemPrompt = _systemPrompt(toEnglish);

    if (PlatformConfig.isAnthropicPlatform(settings.platform)) {
      return _callAnthropic(
        chatUrl, model, settings.apiKey, systemPrompt, trimmed,
      );
    }
    return _callCompatible(
      chatUrl, model, settings.apiKey, systemPrompt, trimmed,
    );
  }

  /// 启发式检测是否为中文：有 CJK 字符且占比 ≥ 拉丁字母
  static bool _isChinese(String text) {
    int cjk = 0, latin = 0;
    for (final cp in text.runes) {
      if ((cp >= 0x4E00 && cp <= 0x9FFF) || // CJK Unified
          (cp >= 0x3400 && cp <= 0x4DBF) || // CJK Ext-A
          (cp >= 0xF900 && cp <= 0xFAFF) || // CJK Compat
          (cp >= 0x3000 && cp <= 0x303F)) {
        // CJK Symbols/Punctuation
        cjk++;
      } else if ((cp >= 0x41 && cp <= 0x5A) || // A-Z
                 (cp >= 0x61 && cp <= 0x7A)) {
        // a-z
        latin++;
      }
    }
    return cjk > 0 && cjk >= latin;
  }

  /// 生成翻译系统提示词
  static String _systemPrompt(bool toEnglish) {
    if (toEnglish) {
      return 'You are a professional Chinese-to-English translator. '
          'Translate the user\'s text into natural, idiomatic English. '
          'Output ONLY the English translation with no additional text, '
          'explanations, or formatting.';
    }
    return '你是一名专业的中英翻译。将用户输入的英文翻译成自然流畅的简体中文。'
        '只输出中文翻译结果，不要添加任何额外文字、解释或格式。';
  }

  /// OpenAI 兼容 API（DeepSeek / OpenAI / 豆包）
  static Future<String> _callCompatible(
    String url,
    String model,
    String apiKey,
    String systemPrompt,
    String userText,
  ) async {
    final uri = Uri.parse(url);
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userText},
      ],
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
            const Duration(seconds: 30),
            onTimeout: () => throw TranslateException('翻译请求超时'),
          );

      final raw = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('━━━ 响应 [${response.statusCode}] ━━━');
        debugPrint(raw);
        throw TranslateException('翻译失败: HTTP ${response.statusCode}');
      }

      debugPrint('━━━ 响应体 ━━━');
      debugPrint(raw);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        debugPrint('翻译结果为空: choices=$choices');
        throw TranslateException('翻译结果为空');
      }
      final content = choices.first['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        debugPrint('翻译内容为空: content=$content');
        throw TranslateException('翻译结果为空');
      }
      return content.trim();
    } catch (e) {
      if (e is TranslateException) rethrow;
      debugPrint('翻译异常: $e');
      throw TranslateException('翻译失败: $e');
    } finally {
      client.close();
    }
  }

  /// Anthropic API（请求体/响应格式不同）
  static Future<String> _callAnthropic(
    String url,
    String model,
    String apiKey,
    String systemPrompt,
    String userText,
  ) async {
    final uri = Uri.parse(url);
    final body = jsonEncode({
      'model': model,
      'max_tokens': 1024,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userText},
      ],
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
            const Duration(seconds: 30),
            onTimeout: () => throw TranslateException('翻译请求超时'),
          );

      final raw = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('━━━ 响应 [${response.statusCode}] ━━━');
        debugPrint(raw);
        throw TranslateException('翻译失败: HTTP ${response.statusCode}');
      }

      debugPrint('━━━ 响应体 ━━━');
      debugPrint(raw);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final contentList = json['content'] as List<dynamic>?;
      if (contentList == null || contentList.isEmpty) {
        debugPrint('Anthropic翻译结果为空: content=$contentList');
        throw TranslateException('翻译结果为空');
      }
      final text = contentList.first['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        debugPrint('Anthropic翻译内容为空');
        throw TranslateException('翻译结果为空');
      }
      return text.trim();
    } catch (e) {
      if (e is TranslateException) rethrow;
      debugPrint('Anthropic翻译异常: $e');
      throw TranslateException('翻译失败: $e');
    } finally {
      client.close();
    }
  }
}

class TranslateException implements Exception {
  TranslateException(this.message);
  final String message;

  @override
  String toString() => message;
}
