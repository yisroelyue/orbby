// 业务 LLM 任务基类
// 面板/功能模块继承此基类，实现 buildSystemPrompt / buildUserPrompt 即可
// 一次性、无状态、返回 JSON

import 'dart:convert';

import 'llm_service.dart';

/// 业务 LLM 任务基类
///
/// 每个子类代表一种无状态的一次性 LLM 请求。
/// [T] 为 parseResponse 的返回类型，默认为 Map<String, dynamic>。
///
/// ```dart
/// class TranslateTask extends LlmTask<Map<String, dynamic>> {
///   @override
///   String buildSystemPrompt() => '你是一个翻译助手，返回 JSON 格式的翻译结果...';
///
///   @override
///   String buildUserPrompt() => '翻译这段文字：...';
/// }
///
/// final result = await TranslateTask().execute();
/// ```
abstract class LlmTask<T> {
  /// 今天日期，由 main() 启动时设置，供子类 prompt 引用
  /// 格式：2025-07-28（星期一）
  static String today = '';

  /// 系统提示词
  String buildSystemPrompt();

  /// 用户提示词
  String buildUserPrompt();

  /// 是否启用联网搜索（DeepSeek 等平台支持），子类可 override
  bool get searchEnabled => false;

  /// 将 LLM 返回的原始文本解析为业务结果
  ///
  /// 默认实现将文本解码为 JSON Map。子类可 override 做结构化转换。
  T parseResponse(String response) {
    final decoded = jsonDecode(response);
    if (decoded is T) return decoded;
    if (decoded is Map<String, dynamic>) return decoded as T;
    throw FormatException('LLM 返回的不是有效 JSON: $response');
  }

  /// 执行任务：构建 prompt → 请求 LLM（JSON 格式）→ 解析结果
  ///
  /// [timeout] 请求超时，默认 45 秒
  /// [retries] 失败重试次数，默认 1
  Future<T> execute({
    Duration timeout = const Duration(seconds: 45),
    int retries = 1,
  }) async {
    final response = await LlmService.ask(
      buildUserPrompt(),
      systemPrompt: buildSystemPrompt(),
      responseFormat: const {'type': 'json_object'},
      searchEnable: searchEnabled ? true : null,
      timeout: timeout,
      retries: retries,
    );
    return parseResponse(response);
  }
}
