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
  static Future<String> ask(
    String prompt, {
    String? systemPrompt,
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

    debugPrint('━━━ LlmService 请求 ━━━');
    debugPrint('平台: ${settings.platform}  模型: $model');

    final client = LLMClient(
      baseURL: chatUrl,
      apiKey: settings.apiKey,
      model: model,
      verbose: kDebugMode,
    );

    final messages = <Message>[
      if (systemPrompt != null)
        Message(role: 'system', content: systemPrompt),
      Message(role: 'user', content: trimmed),
    ];

    final response = await client.chat(messages);
    final content = response.content?.trim() ?? '';
    if (content.isEmpty) {
      throw LlmException('AI 返回为空');
    }
    return content;
  }
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;

  @override
  String toString() => message;
}
