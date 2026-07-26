import 'package:flutter/foundation.dart';

import '../agent/llm_client.dart';
import '../agent/types.dart';
import '../config/platform.dart';
import '../config/settings.dart';

/// 通用 LLM 调用服务，供天气、新闻等面板复用
class LlmService {
  LlmService._();

  /// 发送 prompt 给 LLM，返回纯文本回复
  ///
  /// [prompt] 用户输入的内容
  /// [systemPrompt] 可选的系统提示词，用于约束输出格式
  /// [timeout] 请求超时时间，默认 45 秒
  /// [retries] 失败重试次数，默认 1（共请求 2 次）
  static Future<String> ask(
    String prompt, {
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 45),
    int retries = 1,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      throw LlmException('请输入内容');
    }

    final settings = await SettingsService.load();
    if (settings.apiKey.isEmpty) {
      throw LlmException('请先在设置中配置 API Key');
    }

    final chatUrl = settings.chatUrl.isEmpty
        ? PlatformConfig.defaultChatUrl(settings.platform)
        : settings.chatUrl.trim();
    final model = settings.model.isEmpty
        ? PlatformConfig.defaultChatModel(settings.platform)
        : settings.model;

    final messages = <Message>[
      if (systemPrompt != null)
        Message(role: 'system', content: systemPrompt),
      Message(role: 'user', content: trimmed),
    ];

    LlmException? lastError;
    for (int attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0) {
        debugPrint('━━━ LlmService 第 $attempt 次重试 ━━━');
        // 重试前等待 1 秒，避免频繁请求
        await Future.delayed(const Duration(seconds: 1));
      }

      debugPrint('━━━ LlmService 请求 ━━━');
      debugPrint('平台: ${settings.platform}  模型: $model');

      final client = LLMClient(
        baseURL: chatUrl,
        apiKey: settings.apiKey,
        model: model,
        verbose: kDebugMode,
      );

      try {
        final response = await client.chat(messages).timeout(
          timeout,
          onTimeout: () => throw LlmException('请求超时，请稍后重试'),
        );
        final content = response.content?.trim() ?? '';
        if (content.isEmpty) {
          lastError = LlmException('AI 返回为空');
          continue;
        }
        return content;
      } on LlmException catch (e) {
        lastError = e;
        // 超时或网络错误可以重试，其他错误直接抛出
        if (!e.message.contains('超时') && !e.message.contains('网络')) {
          rethrow;
        }
      }
    }

    throw lastError ?? LlmException('请求失败');
  }
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;

  @override
  String toString() => message;
}
