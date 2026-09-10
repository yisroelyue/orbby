// OpenAI 兼容协议的 LLM 调用封装
// 从 orbby-agent/src/llm/openai-compatible.ts 迁移
// 支持 OpenAI 兼容 API 和 Anthropic API

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/log_service.dart';
import 'types.dart';

enum LLMProvider { openAICompatible, anthropic }

/// LLM 客户端
class LLMClient {
  String baseURL;
  String apiKey;
  String model;
  int maxRetries;

  /// 是否输出请求日志（URL 与请求体）
  bool logRequest;

  /// 是否输出回复日志（响应体与 token 用量）
  bool logResponse;

  /// 日志中隐藏 tools 字段（工具定义列表很长，影响可读性）
  bool hideToolsInLog;
  final LLMProvider provider;

  LLMClient({
    required this.baseURL,
    required this.apiKey,
    required this.model,
    this.maxRetries = 2,
    this.logRequest = true,
    this.logResponse = false,
    this.hideToolsInLog = true,
    this.provider = LLMProvider.openAICompatible,
  });

  // ---- 请求骨架：超时与重试策略集中在此，新增 provider 默认继承 ----

  /// 连接建立超时
  static const _connectTimeout = Duration(seconds: 10);

  /// 发出请求到收到响应头（首字节）的超时
  static const _firstByteTimeout = Duration(seconds: 120);

  /// 非流式响应体整体读取超时（兜底服务端发完响应头后卡住不吐数据）
  static const _bodyReadTimeout = Duration(seconds: 120);

  /// SSE 流空闲超时：连续这么久没收到任何一行就判死连接。
  /// 正常流式输出的行间隔远小于此；每收到一行计时重置。
  static const _sseIdleTimeout = Duration(seconds: 60);

  /// 发送对话请求到 LLM（非流式）
  ///
  /// [responseFormat] 请求响应格式，例如 `{'type': 'json_object'}` 强制返回 JSON。
  /// 对 Anthropic 平台无效（会自动在 system prompt 中追加 JSON 指令）。
  /// [searchEnable] 启用联网搜索（DeepSeek 等平台支持）。
  Future<LLMResponse> chat(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    bool? searchEnable,
  }) async {
    final isAnthropic = provider == LLMProvider.anthropic;

    if (isAnthropic) {
      return _callAnthropic(
        messages,
        tools: tools,
        responseFormat: responseFormat,
      );
    }
    return _callCompatible(
      messages,
      tools: tools,
      responseFormat: responseFormat,
      searchEnable: searchEnable,
    );
  }

  /// 流式发送对话请求到 LLM
  Future<LLMResponse> chatStream(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    bool? searchEnable,
    void Function(String token)? onToken,
  }) async {
    final isAnthropic = provider == LLMProvider.anthropic;

    if (isAnthropic) {
      return _callAnthropicStream(
        messages,
        tools: tools,
        responseFormat: responseFormat,
        onToken: onToken,
      );
    }
    return _callCompatibleStream(
      messages,
      tools: tools,
      responseFormat: responseFormat,
      searchEnable: searchEnable,
      onToken: onToken,
    );
  }

  /// 统一重试骨架：失败按 [_isRetryable] 判定，退避重发。
  /// [retryable] 可覆盖默认判定——流式路径用它拦住"已流出部分内容"的重试
  /// （重试会整段重发，导致 UI 文本重复）。
  Future<T> _withRetry<T>(
    Future<T> Function() attempt, {
    bool Function(Object error)? retryable,
  }) async {
    Exception? lastError;
    for (var i = 0; i <= maxRetries; i++) {
      try {
        return await attempt();
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        final canRetry = retryable?.call(e) ?? _isRetryable(e);
        if (i < maxRetries && canRetry) {
          await Future.delayed(Duration(seconds: i + 1));
        }
      }
    }
    throw lastError!;
  }

  /// 发送 POST，收到响应头后交给 [handle] 处理，完毕统一关闭 client。
  /// 连接超时与首字节超时在这里统一管。
  Future<T> _post<T>({
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required String logLabel,
    required Future<T> Function(HttpClientResponse response) handle,
  }) async {
    if (logRequest) {
      LogService.info('━━━ $logLabel ━━━', category: 'llm');
      LogService.info('URL: $baseURL', category: 'llm');
      LogService.info(_formatBodyForLog(body), category: 'llm');
    }
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = await client.postUrl(Uri.parse(baseURL));
      request.headers.contentType = ContentType.json;
      headers.forEach((name, value) => request.headers.set(name, value));
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close().timeout(
        _firstByteTimeout,
        onTimeout: () => throw TimeoutException('请求超时'),
      );
      return await handle(response);
    } finally {
      client.close();
    }
  }

  /// 读取非流式响应体（整体超时兜底）
  Future<String> _readBody(HttpClientResponse response) {
    return response
        .transform(utf8.decoder)
        .join()
        .timeout(
          _bodyReadTimeout,
          onTimeout: () => throw TimeoutException('响应体读取超时'),
        );
  }

  /// SSE 行流（空闲超时：每收到一行重置计时，卡死的连接及时报错走重试）
  Stream<String> _sseLines(HttpClientResponse response) {
    return response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(
          _sseIdleTimeout,
          onTimeout: (sink) {
            sink.addError(
              TimeoutException(
                '响应流超时（${_sseIdleTimeout.inSeconds} 秒未收到数据）',
              ),
            );
            sink.close();
          },
        );
  }

  /// 检测当前平台
  String _detectPlatform() {
    // 从 baseURL 推断平台
    if (baseURL.contains('anthropic')) return 'anthropic';
    if (baseURL.contains('deepseek')) return 'deepseek';
    if (baseURL.contains('openai')) return 'openai';
    if (baseURL.contains('volces')) return 'doubao';
    if (baseURL.contains('mimo')) return 'mimo';
    if (baseURL.contains('dashscope')) return 'qwen';
    if (baseURL.contains('moonshot')) return 'kimi';
    if (baseURL.contains('bigmodel')) return 'zhipu';
    return 'deepseek'; // 默认
  }

  bool _isRetryable(Object error) {
    final message = '$error'.toLowerCase();
    if (message.contains('(400)') ||
        message.contains('(401)') ||
        message.contains('(403)') ||
        message.contains('(404)') ||
        message.contains('(422)'))
      return false;
    return message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('(408)') ||
        message.contains('(429)') ||
        RegExp(r'\(5\d\d\)').hasMatch(message);
  }

  /// 格式化请求体用于日志输出
  String _formatBodyForLog(Map<String, dynamic> body) {
    if (!hideToolsInLog) {
      return const JsonEncoder.withIndent('  ').convert(body);
    }
    final logBody = Map<String, dynamic>.from(body);
    if (logBody['tools'] is List) {
      final tools = logBody['tools'] as List;
      final names = tools
          .map((t) => t['function']?['name'] ?? t['name'] ?? '?')
          .toList();
      logBody['tools'] = '[${names.length} 个工具: ${names.join(', ')}]';
    }
    logBody.remove('tool_choice');
    return const JsonEncoder.withIndent('  ').convert(logBody);
  }

  // ---- OpenAI 兼容协议 ----

  /// 组装 OpenAI 兼容协议请求体
  Map<String, dynamic> _compatibleBody(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    bool? searchEnable,
    required bool stream,
  }) {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': 0.1,
      if (stream) 'stream': true,
    };

    if (responseFormat != null) {
      body['response_format'] = responseFormat;
    }

    if (searchEnable == true) {
      body['search_enable'] = true;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toJson()).toList();
      body['tool_choice'] = 'auto';
    }

    return body;
  }

  /// OpenAI 兼容 API（非流式）
  Future<LLMResponse> _callCompatible(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    bool? searchEnable,
  }) {
    final body = _compatibleBody(
      messages,
      tools: tools,
      responseFormat: responseFormat,
      searchEnable: searchEnable,
      stream: false,
    );
    return _withRetry(
      () => _post(
        headers: {'Authorization': 'Bearer $apiKey'},
        body: body,
        logLabel: 'LLM 请求',
        handle: _parseCompatibleResponse,
      ),
    );
  }

  /// 解析 OpenAI 兼容非流式响应
  Future<LLMResponse> _parseCompatibleResponse(
    HttpClientResponse response,
  ) async {
    final raw = await _readBody(response);

    if (response.statusCode != 200) {
      throw HttpException('LLM API 错误 (${response.statusCode}): $raw');
    }

    if (logResponse) {
      LogService.info('━━━ LLM 响应 ━━━', category: 'llm');
      LogService.info(raw, category: 'llm');
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('AI 返回为空');
    }

    final message = choices.first['message'] as Map<String, dynamic>;
    var toolCalls = _parseToolCalls(message['tool_calls']);

    // 兜底：解析 DeepSeek <execute_tool> 文本格式
    final textContent = message['content'] as String?;
    if (toolCalls == null &&
        textContent != null &&
        textContent.contains('<execute_tool>')) {
      toolCalls = _parseExecuteToolTags(textContent);
    }

    // 打印 token 使用情况
    if (logResponse && json['usage'] != null) {
      final usage = json['usage'] as Map<String, dynamic>;
      LogService.info(
        '  Token: prompt=${usage['prompt_tokens']}, completion=${usage['completion_tokens']}, total=${usage['total_tokens']}',
        category: 'llm',
      );
    }

    return LLMResponse(
      role: message['role'] as String? ?? 'assistant',
      content: (toolCalls != null) ? null : textContent,
      toolCalls: toolCalls,
    );
  }

  /// OpenAI 兼容 API（流式）
  Future<LLMResponse> _callCompatibleStream(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    bool? searchEnable,
    void Function(String token)? onToken,
  }) {
    final body = _compatibleBody(
      messages,
      tools: tools,
      responseFormat: responseFormat,
      searchEnable: searchEnable,
      stream: true,
    );
    // 本轮已流出过部分内容时不再重试：重试会整段重发，UI 文本会重复
    var streamedTokens = false;
    return _withRetry(
      () => _post(
        headers: {'Authorization': 'Bearer $apiKey'},
        body: body,
        logLabel: 'LLM 流式请求',
        handle: (response) => _parseCompatibleStreamResponse(
          response,
          onToken: (token) {
            streamedTokens = true;
            onToken?.call(token);
          },
        ),
      ),
      retryable: (error) => !streamedTokens && _isRetryable(error),
    );
  }

  /// 解析 OpenAI 兼容 SSE 流
  Future<LLMResponse> _parseCompatibleStreamResponse(
    HttpClientResponse response, {
    void Function(String token)? onToken,
  }) async {
    if (response.statusCode != 200) {
      final raw = await _readBody(response);
      throw HttpException('LLM API 错误 (${response.statusCode}): $raw');
    }

    // 解析 SSE 流
    var content = '';
    var reasoningContent = '';
    final toolCalls = <int, _ToolCallBuilder>{};

    await for (final line in _sseLines(response)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;

      final data = trimmed.substring(6);
      if (data == '[DONE]') continue;

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;

        final delta = choices.first['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        // 累积思考过程
        if (delta['reasoning_content'] != null) {
          reasoningContent += delta['reasoning_content'] as String;
        }

        // 累积文本内容
        if (delta['content'] != null) {
          final token = delta['content'] as String;
          content += token;
          onToken?.call(token);
        }

        // 累积工具调用
        if (delta['tool_calls'] != null) {
          final deltaToolCalls = delta['tool_calls'] as List<dynamic>;
          for (final tc in deltaToolCalls) {
            final idx = tc['index'] as int? ?? 0;
            if (!toolCalls.containsKey(idx)) {
              toolCalls[idx] = _ToolCallBuilder();
            }
            final builder = toolCalls[idx]!;
            if (tc['id'] != null) builder.id = tc['id'] as String;
            if (tc['function']?['name'] != null) {
              builder.name = tc['function']['name'] as String;
            }
            if (tc['function']?['arguments'] != null) {
              builder.arguments += tc['function']['arguments'] as String;
            }
          }
        }
      } catch (_) {
        // 跳过解析失败的行
      }
    }

    // 构建返回值
    var finalToolCalls = _buildToolCalls(toolCalls);

    // 兜底：如果结构化 tool_calls 为空，但 content 中包含
    // <execute_tool> 标签（DeepSeek 某些模型的文本格式工具调用），
    // 尝试从文本中解析工具调用。
    if (finalToolCalls == null && content.contains('<execute_tool>')) {
      finalToolCalls = _parseExecuteToolTags(content);
      if (finalToolCalls != null) {
        // 工具调用已从文本中解析，清除 content 避免被当作普通回复
        content = '';
      }
    }

    if (logResponse) {
      LogService.info('━━━ LLM 流式回复 ━━━', category: 'llm');
      if (content.isNotEmpty) {
        LogService.info(content, category: 'llm');
      }
      if (reasoningContent.isNotEmpty) {
        LogService.info('思考过程: $reasoningContent', category: 'llm');
      }
      if (finalToolCalls != null) {
        LogService.info(
          '工具调用: ${finalToolCalls.map((t) => t.name).join(', ')}',
          category: 'llm',
        );
      }
    }
    return LLMResponse(
      role: 'assistant',
      content: content.isEmpty ? null : content,
      reasoningContent: reasoningContent.isEmpty
          ? null
          : reasoningContent,
      toolCalls: finalToolCalls,
    );
  }

  // ---- Anthropic 协议 ----

  /// 组装 Anthropic 协议请求体（system 在顶层，messages 不包含 system）
  Map<String, dynamic> _anthropicBody(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    required bool stream,
  }) {
    final systemMessage = messages.where((m) => m.role == 'system').firstOrNull;

    // 如果请求 JSON 格式，在 system prompt 中追加指令
    var systemContent = systemMessage?.content ?? '';
    if (responseFormat != null && responseFormat['type'] == 'json_object') {
      systemContent += '\n\n请严格以 JSON 格式输出，不要包含任何额外文字或 Markdown 标记。';
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': messages
          .where((m) => m.role != 'system')
          .map((m) => m.toJson())
          .toList(),
      if (stream) 'stream': true,
    };

    if (systemContent.isNotEmpty) {
      body['system'] = systemContent;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools
          .map(
            (t) => {
              'name': t.name,
              'description': t.description,
              'input_schema': t.parameters,
            },
          )
          .toList();
    }

    return body;
  }

  /// Anthropic API（非流式）
  Future<LLMResponse> _callAnthropic(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
  }) {
    final body = _anthropicBody(
      messages,
      tools: tools,
      responseFormat: responseFormat,
      stream: false,
    );
    return _withRetry(
      () => _post(
        headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
        body: body,
        logLabel: 'Anthropic 请求',
        handle: _parseAnthropicResponse,
      ),
    );
  }

  /// 解析 Anthropic 非流式响应
  Future<LLMResponse> _parseAnthropicResponse(HttpClientResponse response) async {
    final raw = await _readBody(response);

    if (response.statusCode != 200) {
      throw HttpException(
        'Anthropic API 错误 (${response.statusCode}): $raw',
      );
    }

    if (logResponse) {
      LogService.info('━━━ Anthropic 响应 ━━━', category: 'llm');
      LogService.info(raw, category: 'llm');
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final contentList = json['content'] as List<dynamic>?;
    if (contentList == null || contentList.isEmpty) {
      throw const FormatException('AI 返回为空');
    }

    // 解析内容
    var textContent = '';
    final toolCalls = <ToolCall>[];

    for (final block in contentList) {
      final type = block['type'] as String?;
      if (type == 'text') {
        textContent += block['text'] as String? ?? '';
      } else if (type == 'tool_use') {
        toolCalls.add(
          ToolCall(
            id: block['id'] as String,
            name: block['name'] as String,
            arguments: Map<String, dynamic>.from(block['input'] as Map),
          ),
        );
      }
    }

    return LLMResponse(
      role: 'assistant',
      content: textContent.isEmpty ? null : textContent,
      toolCalls: toolCalls.isEmpty ? null : toolCalls,
    );
  }

  /// Anthropic API（流式）
  Future<LLMResponse> _callAnthropicStream(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    void Function(String token)? onToken,
  }) {
    final body = _anthropicBody(
      messages,
      tools: tools,
      responseFormat: responseFormat,
      stream: true,
    );
    // 本轮已流出过部分内容时不再重试：重试会整段重发，UI 文本会重复
    var streamedTokens = false;
    return _withRetry(
      () => _post(
        headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
        body: body,
        logLabel: 'Anthropic 流式请求',
        handle: (response) => _parseAnthropicStreamResponse(
          response,
          onToken: (text) {
            streamedTokens = true;
            onToken?.call(text);
          },
        ),
      ),
      retryable: (error) => !streamedTokens && _isRetryable(error),
    );
  }

  /// 解析 Anthropic SSE 流
  Future<LLMResponse> _parseAnthropicStreamResponse(
    HttpClientResponse response, {
    void Function(String token)? onToken,
  }) async {
    if (response.statusCode != 200) {
      final raw = await _readBody(response);
      throw HttpException(
        'Anthropic API 错误 (${response.statusCode}): $raw',
      );
    }

    // 解析 SSE 流
    var content = '';
    final toolUseBlocks = <int, _AnthropicToolCallBuilder>{};

    await for (final line in _sseLines(response)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;

      final data = trimmed.substring(6);
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final type = json['type'] as String?;

        if (type == 'content_block_start') {
          final block = json['content_block'] as Map<String, dynamic>?;
          if (block != null && block['type'] == 'tool_use') {
            final idx = json['index'] as int? ?? 0;
            toolUseBlocks[idx] = _AnthropicToolCallBuilder(
              id: block['id'] as String? ?? '',
              name: block['name'] as String? ?? '',
            );
          }
        } else if (type == 'content_block_delta') {
          final idx = json['index'] as int? ?? 0;
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta != null) {
            if (delta['type'] == 'text_delta') {
              final text = delta['text'] as String? ?? '';
              content += text;
              onToken?.call(text);
            } else if (delta['type'] == 'input_json_delta') {
              toolUseBlocks[idx]?.inputJson +=
                  delta['partial_json'] as String? ?? '';
            }
          }
        }
        // content_block_stop 不需要额外处理，数据已累积
      } catch (_) {
        // 跳过解析失败的行
      }
    }

    // 构建工具调用列表
    final toolCalls = <ToolCall>[];
    for (final entry
        in toolUseBlocks.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final builder = entry.value;
      Map<String, dynamic> input = {};
      try {
        if (builder.inputJson.isNotEmpty) {
          input = Map<String, dynamic>.from(
            jsonDecode(builder.inputJson) as Map,
          );
        }
      } catch (_) {}
      toolCalls.add(
        ToolCall(id: builder.id, name: builder.name, arguments: input),
      );
    }

    if (logResponse) {
      LogService.info('━━━ Anthropic 流式回复 ━━━', category: 'llm');
      if (content.isNotEmpty) {
        LogService.info(content, category: 'llm');
      }
      if (toolCalls.isNotEmpty) {
        LogService.info(
          '工具调用: ${toolCalls.map((t) => t.name).join(', ')}',
          category: 'llm',
        );
      }
    }
    return LLMResponse(
      role: 'assistant',
      content: content.isEmpty ? null : content,
      toolCalls: toolCalls.isEmpty ? null : toolCalls,
    );
  }

  // ---- 通用解析 ----

  /// 解析 OpenAI 格式的 tool_calls
  List<ToolCall>? _parseToolCalls(dynamic toolCallsJson) {
    if (toolCallsJson == null) return null;
    final toolCallsList = toolCallsJson as List<dynamic>;
    if (toolCallsList.isEmpty) return null;

    return toolCallsList.map((tc) {
      final function = tc['function'] as Map<String, dynamic>;
      return ToolCall(
        id: tc['id'] as String,
        name: function['name'] as String,
        arguments: _parseArguments(function['arguments'] as String),
      );
    }).toList();
  }

  /// 解析 JSON 字符串参数
  Map<String, dynamic> _parseArguments(String args) {
    try {
      return Map<String, dynamic>.from(jsonDecode(args) as Map);
    } catch (_) {
      return {};
    }
  }

  /// 从 DeepSeek <execute_tool> 文本标签中解析工具调用
  List<ToolCall>? _parseExecuteToolTags(String content) {
    final pattern = RegExp(
      r'<execute_tool>\s*'
      r'<tool_name>(.*?)</tool_name>'
      r'(?:\s*<arguments>(.*?)</arguments>)?'
      r'\s*</execute_tool>',
      dotAll: true,
    );

    final matches = pattern.allMatches(content).toList();
    if (matches.isEmpty) return null;

    return matches.map((m) {
      final name = m.group(1)?.trim() ?? '';
      final argsStr = m.group(2)?.trim() ?? '';
      Map<String, dynamic> args = {};
      if (argsStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(argsStr);
          if (decoded is Map<String, dynamic>) args = decoded;
        } catch (_) {}
      }
      return ToolCall(
        id: 'call_${name}_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        arguments: args,
      );
    }).toList();
  }

  /// 构建 tool_calls 列表
  List<ToolCall>? _buildToolCalls(Map<int, _ToolCallBuilder> builders) {
    if (builders.isEmpty) return null;

    final sortedKeys = builders.keys.toList()..sort();
    return sortedKeys.map((idx) {
      final builder = builders[idx]!;
      return ToolCall(
        id: builder.id,
        name: builder.name,
        arguments: _parseArguments(builder.arguments),
      );
    }).toList();
  }
}

/// 工具调用构建器（用于 OpenAI 兼容流式解析）
class _ToolCallBuilder {
  String id = '';
  String name = '';
  String arguments = '';
}

/// Anthropic 工具调用构建器（用于流式解析）
class _AnthropicToolCallBuilder {
  String id;
  String name;
  String inputJson = '';

  _AnthropicToolCallBuilder({required this.id, required this.name});
}
