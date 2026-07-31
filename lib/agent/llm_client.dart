// OpenAI 兼容协议的 LLM 调用封装
// 从 orbby-agent/src/llm/openai-compatible.ts 迁移
// 支持 OpenAI 兼容 API 和 Anthropic API

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'types.dart';

enum LLMProvider { openAICompatible, anthropic }

/// LLM 客户端
class LLMClient {
  String baseURL;
  String apiKey;
  String model;
  int maxRetries;
  bool verbose;

  /// 日志中隐藏 tools 字段（工具定义列表很长，影响可读性）
  bool hideToolsInLog;
  final LLMProvider provider;

  LLMClient({
    required this.baseURL,
    required this.apiKey,
    required this.model,
    this.maxRetries = 2,
    this.verbose = false,
    this.hideToolsInLog = true,
    this.provider = LLMProvider.openAICompatible,
  });

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

  /// OpenAI 兼容 API（非流式）
  Future<LLMResponse> _callCompatible(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    bool? searchEnable,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': 0.1,
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

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ LLM 请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(_formatBodyForLog(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final request = await client.postUrl(Uri.parse(url));
          request.headers.contentType = ContentType.json;
          request.headers.set('Authorization', 'Bearer $apiKey');
          final bytes = utf8.encode(jsonEncode(body));
          request.headers.set('Content-Length', bytes.length.toString());
          request.add(bytes);

          final response = await request.close().timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException('请求超时'),
          );

          final raw = await response.transform(utf8.decoder).join();

          if (response.statusCode != 200) {
            throw HttpException('LLM API 错误 (${response.statusCode}): $raw');
          }

          if (verbose) {
            debugPrint('━━━ LLM 响应 ━━━');
            debugPrint(raw);
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

          final result = LLMResponse(
            role: message['role'] as String? ?? 'assistant',
            content: (toolCalls != null) ? null : textContent,
            toolCalls: toolCalls,
          );

          // 打印 token 使用情况
          if (verbose && json['usage'] != null) {
            final usage = json['usage'] as Map<String, dynamic>;
            debugPrint(
              '  Token: prompt=${usage['prompt_tokens']}, completion=${usage['completion_tokens']}, total=${usage['total_tokens']}',
            );
          }

          return result;
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (attempt < maxRetries && _isRetryable(e)) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    throw lastError!;
  }

  /// OpenAI 兼容 API（流式）
  Future<LLMResponse> _callCompatibleStream(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    bool? searchEnable,
    void Function(String token)? onToken,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': 0.1,
      'stream': true,
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

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ LLM 流式请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(_formatBodyForLog(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final request = await client.postUrl(Uri.parse(url));
          request.headers.contentType = ContentType.json;
          request.headers.set('Authorization', 'Bearer $apiKey');
          final bytes = utf8.encode(jsonEncode(body));
          request.headers.set('Content-Length', bytes.length.toString());
          request.add(bytes);

          final response = await request.close().timeout(
            const Duration(seconds: 120),
            onTimeout: () => throw TimeoutException('请求超时'),
          );

          if (response.statusCode != 200) {
            final raw = await response.transform(utf8.decoder).join();
            throw HttpException('LLM API 错误 (${response.statusCode}): $raw');
          }

          // 解析 SSE 流
          var content = '';
          var reasoningContent = '';
          final toolCalls = <int, _ToolCallBuilder>{};

          final lines = response
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          await for (final line in lines) {
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

          return LLMResponse(
            role: 'assistant',
            content: content.isEmpty ? null : content,
            reasoningContent: reasoningContent.isEmpty
                ? null
                : reasoningContent,
            toolCalls: finalToolCalls,
          );
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (attempt < maxRetries && _isRetryable(e)) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    throw lastError!;
  }

  /// Anthropic API（非流式）
  Future<LLMResponse> _callAnthropic(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
  }) async {
    // Anthropic 格式：system 放在顶层，messages 不包含 system
    final systemMessage = messages.where((m) => m.role == 'system').firstOrNull;
    final userMessages = messages
        .where((m) => m.role != 'system')
        .map((m) => m.toJson())
        .toList();

    // 如果请求 JSON 格式，在 system prompt 中追加指令
    var systemContent = systemMessage?.content ?? '';
    if (responseFormat != null && responseFormat['type'] == 'json_object') {
      systemContent += '\n\n请严格以 JSON 格式输出，不要包含任何额外文字或 Markdown 标记。';
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': userMessages,
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

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ Anthropic 请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(_formatBodyForLog(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final request = await client.postUrl(Uri.parse(url));
          request.headers.contentType = ContentType.json;
          request.headers.set('x-api-key', apiKey);
          request.headers.set('anthropic-version', '2023-06-01');
          final bytes = utf8.encode(jsonEncode(body));
          request.headers.set('Content-Length', bytes.length.toString());
          request.add(bytes);

          final response = await request.close().timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException('请求超时'),
          );

          final raw = await response.transform(utf8.decoder).join();

          if (response.statusCode != 200) {
            throw HttpException(
              'Anthropic API 错误 (${response.statusCode}): $raw',
            );
          }

          if (verbose) {
            debugPrint('━━━ Anthropic 响应 ━━━');
            debugPrint(raw);
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
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (attempt < maxRetries && _isRetryable(e)) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    throw lastError!;
  }

  /// Anthropic API（流式）
  Future<LLMResponse> _callAnthropicStream(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    Map<String, dynamic>? responseFormat,
    void Function(String token)? onToken,
  }) async {
    // Anthropic 格式：system 放在顶层，messages 不包含 system
    final systemMessage = messages.where((m) => m.role == 'system').firstOrNull;
    final userMessages = messages
        .where((m) => m.role != 'system')
        .map((m) => m.toJson())
        .toList();

    // 如果请求 JSON 格式，在 system prompt 中追加指令
    var systemContent = systemMessage?.content ?? '';
    if (responseFormat != null && responseFormat['type'] == 'json_object') {
      systemContent += '\n\n请严格以 JSON 格式输出，不要包含任何额外文字或 Markdown 标记。';
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': userMessages,
      'stream': true,
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

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ Anthropic 流式请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(_formatBodyForLog(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final request = await client.postUrl(Uri.parse(url));
          request.headers.contentType = ContentType.json;
          request.headers.set('x-api-key', apiKey);
          request.headers.set('anthropic-version', '2023-06-01');
          final bytes = utf8.encode(jsonEncode(body));
          request.headers.set('Content-Length', bytes.length.toString());
          request.add(bytes);

          final response = await request.close().timeout(
            const Duration(seconds: 120),
            onTimeout: () => throw TimeoutException('请求超时'),
          );

          if (response.statusCode != 200) {
            final raw = await response.transform(utf8.decoder).join();
            throw HttpException(
              'Anthropic API 错误 (${response.statusCode}): $raw',
            );
          }

          // 解析 SSE 流
          var content = '';
          final toolUseBlocks = <int, _AnthropicToolCallBuilder>{};

          final lines = response
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          await for (final line in lines) {
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

          return LLMResponse(
            role: 'assistant',
            content: content.isEmpty ? null : content,
            toolCalls: toolCalls.isEmpty ? null : toolCalls,
          );
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (attempt < maxRetries && _isRetryable(e)) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    throw lastError!;
  }

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
