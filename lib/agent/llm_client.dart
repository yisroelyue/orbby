// OpenAI 兼容协议的 LLM 调用封装
// 从 orbby-agent/src/llm/openai-compatible.ts 迁移
// 支持 OpenAI 兼容 API 和 Anthropic API

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import 'types.dart';

/// LLM 客户端配置
class LLMClientOptions {
  final String? baseURL;
  final String? apiKey;
  final String? model;
  final int maxRetries;
  final bool verbose;

  const LLMClientOptions({
    this.baseURL,
    this.apiKey,
    this.model,
    this.maxRetries = 2,
    this.verbose = false,
  });
}

/// LLM 客户端
class LLMClient {
  String baseURL;
  String apiKey;
  String model;
  int maxRetries;
  bool verbose;

  LLMClient({
    required this.baseURL,
    required this.apiKey,
    required this.model,
    this.maxRetries = 2,
    this.verbose = false,
  });

  /// 从设置创建客户端
  static Future<LLMClient> fromSettings({
    String? compactModel,
    bool verbose = false,
  }) async {
    // 延迟导入避免循环依赖
    final settings = await _loadSettings();
    final platform = settings['platform'] as String;
    final chatUrl = (settings['chatUrl'] as String?)?.isNotEmpty == true
        ? settings['chatUrl'] as String
        : PlatformConfig.defaultChatUrl(platform);
    final model = (settings['model'] as String?)?.isNotEmpty == true
        ? settings['model'] as String
        : PlatformConfig.defaultChatModel(platform);
    final apiKey = settings['apiKey'] as String;

    return LLMClient(
      baseURL: chatUrl,
      apiKey: apiKey,
      model: compactModel ?? model,
      verbose: verbose,
    );
  }

  /// 加载设置
  static Future<Map<String, dynamic>> _loadSettings() async {
    // 这里需要导入 SettingsService，但为了避免循环依赖，我们直接返回配置
    // 实际使用时应该通过依赖注入传入
    throw UnimplementedError('请使用 fromSettings 工厂方法或直接传入参数');
  }

  /// 发送对话请求到 LLM（非流式）
  Future<LLMResponse> chat(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
  }) async {
    final isAnthropic = PlatformConfig.isAnthropicPlatform(_detectPlatform());

    if (isAnthropic) {
      return _callAnthropic(messages, tools: tools);
    }
    return _callCompatible(messages, tools: tools);
  }

  /// 流式发送对话请求到 LLM
  Future<LLMResponse> chatStream(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
    void Function(String token)? onToken,
  }) async {
    final isAnthropic = PlatformConfig.isAnthropicPlatform(_detectPlatform());

    if (isAnthropic) {
      return _callAnthropicStream(messages, tools: tools, onToken: onToken);
    }
    return _callCompatibleStream(messages, tools: tools, onToken: onToken);
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

  /// OpenAI 兼容 API（非流式）
  Future<LLMResponse> _callCompatible(
    List<Message> messages, {
    List<ToolCallDefinition>? tools,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': 0.1,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toJson()).toList();
      body['tool_choice'] = 'auto';
    }

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ LLM 请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(const JsonEncoder.withIndent('  ').convert(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
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
          final result = LLMResponse(
            role: message['role'] as String? ?? 'assistant',
            content: message['content'] as String?,
            toolCalls: _parseToolCalls(message['tool_calls']),
          );

          // 打印 token 使用情况
          if (verbose && json['usage'] != null) {
            final usage = json['usage'] as Map<String, dynamic>;
            debugPrint('  Token: prompt=${usage['prompt_tokens']}, completion=${usage['completion_tokens']}, total=${usage['total_tokens']}');
          }

          return result;
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (attempt < maxRetries) {
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
    void Function(String token)? onToken,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': 0.1,
      'stream': true,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toJson()).toList();
      body['tool_choice'] = 'auto';
    }

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ LLM 流式请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(const JsonEncoder.withIndent('  ').convert(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
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
          return LLMResponse(
            role: 'assistant',
            content: content.isEmpty ? null : content,
            reasoningContent: reasoningContent.isEmpty ? null : reasoningContent,
            toolCalls: _buildToolCalls(toolCalls),
          );
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (attempt < maxRetries) {
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
  }) async {
    // Anthropic 格式：system 放在顶层，messages 不包含 system
    final systemMessage = messages.where((m) => m.role == 'system').firstOrNull;
    final userMessages = messages
        .where((m) => m.role != 'system')
        .map((m) => m.toJson())
        .toList();

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': userMessages,
    };

    if (systemMessage != null) {
      body['system'] = systemMessage.content;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools.map((t) => {
        'name': t.name,
        'description': t.description,
        'input_schema': t.parameters,
      }).toList();
    }

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ Anthropic 请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(const JsonEncoder.withIndent('  ').convert(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
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
            throw HttpException('Anthropic API 错误 (${response.statusCode}): $raw');
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
              toolCalls.add(ToolCall(
                id: block['id'] as String,
                name: block['name'] as String,
                arguments: Map<String, dynamic>.from(block['input'] as Map),
              ));
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
        if (attempt < maxRetries) {
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
    void Function(String token)? onToken,
  }) async {
    // Anthropic 格式：system 放在顶层，messages 不包含 system
    final systemMessage = messages.where((m) => m.role == 'system').firstOrNull;
    final userMessages = messages
        .where((m) => m.role != 'system')
        .map((m) => m.toJson())
        .toList();

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': userMessages,
      'stream': true,
    };

    if (systemMessage != null) {
      body['system'] = systemMessage.content;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools.map((t) => {
        'name': t.name,
        'description': t.description,
        'input_schema': t.parameters,
      }).toList();
    }

    final url = baseURL;
    if (verbose) {
      debugPrint('━━━ Anthropic 流式请求 ━━━');
      debugPrint('URL: $url');
      debugPrint(const JsonEncoder.withIndent('  ').convert(body));
    }

    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
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
            throw HttpException('Anthropic API 错误 (${response.statusCode}): $raw');
          }

          // 解析 SSE 流
          var content = '';
          final toolCalls = <ToolCall>[];

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

              if (type == 'content_block_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  if (delta['type'] == 'text_delta') {
                    final text = delta['text'] as String? ?? '';
                    content += text;
                    onToken?.call(text);
                  }
                }
              }
            } catch (_) {
              // 跳过解析失败的行
            }
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
        if (attempt < maxRetries) {
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

/// 工具调用构建器（用于流式解析）
class _ToolCallBuilder {
  String id = '';
  String name = '';
  String arguments = '';
}
