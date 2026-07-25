import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/agent_core.dart';
import '../agent/llm_client.dart';
import '../agent/tool_registry.dart';
import '../agent/tools/builtin_tools.dart';
import '../agent/types.dart' as agent_types;
import '../config/platform.dart';
import '../config/settings.dart';

class AgentService {
  AgentService._();

  static Agent? _agent;
  static String? _currentPlatform;
  static String? _currentModel;

  /// 获取或创建 Agent 实例
  static Future<Agent> _getAgent({
    String? compactModel,
    bool forceRecreate = false,
  }) async {
    final settings = await SettingsService.load();
    final platform = settings.platform;
    final model = settings.model.isEmpty
        ? PlatformConfig.defaultChatModel(platform)
        : settings.model;

    // 如果配置变化或需要重建
    if (_agent == null || forceRecreate ||
        _currentPlatform != platform || _currentModel != model) {
      final chatUrl = settings.chatUrl.isEmpty
          ? PlatformConfig.defaultChatUrl(platform)
          : settings.chatUrl.trim();

      // 创建主 LLM 客户端
      final llm = LLMClient(
        baseURL: chatUrl,
        apiKey: settings.apiKey,
        model: model,
        verbose: kDebugMode,
      );

      // 创建压缩 LLM 客户端（使用轻量模型）
      final compactModelName = compactModel ?? _getDefaultCompactModel(platform);
      final compactLLM = LLMClient(
        baseURL: chatUrl,
        apiKey: settings.apiKey,
        model: compactModelName,
        verbose: false,
      );

      // 创建工具注册中心
      final registry = ToolRegistry();
      registerBuiltinTools(registry);

      // 创建 Agent
      _agent = Agent(
        llm: llm,
        compactLLM: compactLLM,
        registry: registry,
        conversationOptions: const agent_types.ConversationOptions(
          maxTokens: 32000,
          keepRecentTurns: 3,
          summaryMaxChars: 2400,
          maxToolResultChars: 12000,
        ),
      );

      // 初始化
      _agent!.init();

      _currentPlatform = platform;
      _currentModel = model;

      debugPrint('━━━ Agent 初始化完成 ━━━');
      debugPrint('平台: $platform  模型: $model  压缩模型: $compactModelName');
    }

    return _agent!;
  }

  /// 获取默认压缩模型
  static String _getDefaultCompactModel(String platform) {
    return switch (platform) {
      'deepseek' => 'deepseek-chat',
      'openai' => 'gpt-3.5-turbo',
      'anthropic' => 'claude-3-haiku-20240307',
      'doubao' => 'doubao-lite-32k',
      'mimo' => 'mimo-mini',
      'qwen' => 'qwen-turbo',
      'kimi' => 'moonshot-v1-8k',
      'zhipu' => 'glm-4-flash',
      _ => 'deepseek-chat',
    };
  }

  /// 发送消息到 AI，返回回复文本（非流式，一次性返回）
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

    final agent = await _getAgent();

    // 如果有历史消息，添加到对话中
    if (history.isNotEmpty) {
      for (final msg in history) {
        final role = msg['role'] ?? 'user';
        final content = msg['content'] ?? '';
        if (role == 'user') {
          agent.conversation.addUserMessage(content);
        } else if (role == 'assistant') {
          agent.conversation.addAssistantMessage(
            agent_types.LLMResponse(content: content),
          );
        }
      }
    }

    // 处理消息
    return agent.processMessage(trimmed);
  }

  /// 发送消息到 AI，返回流式 token（边生成边返回）
  static Stream<String> chatStream(
    String userText, {
    String mode = 'accept',
    List<Map<String, String>> history = const [],
  }) async* {
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      throw AgentException('消息为空');
    }

    final settings = await SettingsService.load();
    if (settings.apiKey.isEmpty) {
      throw AgentException('请先在设置中配置 API Key');
    }

    final agent = await _getAgent();

    // 如果有历史消息，添加到对话中
    if (history.isNotEmpty) {
      for (final msg in history) {
        final role = msg['role'] ?? 'user';
        final content = msg['content'] ?? '';
        if (role == 'user') {
          agent.conversation.addUserMessage(content);
        } else if (role == 'assistant') {
          agent.conversation.addAssistantMessage(
            agent_types.LLMResponse(content: content),
          );
        }
      }
    }

    // 使用 StreamController 处理流式输出
    final controller = StreamController<String>();
    var hasStreamedTokens = false;

    // 异步处理消息
    agent.processMessage(trimmed, onToken: (token) {
      hasStreamedTokens = true;
      controller.add(token);
    }).then((result) {
      // 只有当没有流式输出时，才添加最终结果
      if (!controller.isClosed && !hasStreamedTokens) {
        controller.add(result);
        controller.close();
      } else if (!controller.isClosed) {
        controller.close();
      }
    }).catchError((error) {
      if (!controller.isClosed) {
        controller.addError(error is Exception ? error : Exception('$error'));
        controller.close();
      }
    });

    yield* controller.stream;
  }

  /// 重置对话
  static void resetConversation() {
    _agent?.conversation.reset();
  }

  /// 获取对话状态
  static agent_types.ConversationStats? getConversationStats() {
    return _agent?.conversation.stats();
  }

  /// 手动触发上下文压缩
  static Future<String> compact() async {
    final agent = await _getAgent();
    return agent.handleCompact();
  }

  /// 获取可用工具列表
  static List<Map<String, dynamic>> getAvailableTools() {
    if (_agent == null) return [];
    return _agent!.registry.getToolDefinitions()
        .map((t) => {
          'name': t.name,
          'description': t.description,
        })
        .toList();
  }

  /// 强制重新创建 Agent（配置变化时调用）
  static Future<void> recreate() async {
    _agent = null;
    _currentPlatform = null;
    _currentModel = null;
    await _getAgent(forceRecreate: true);
  }
}

class AgentException implements Exception {
  AgentException(this.message);
  final String message;

  @override
  String toString() => message;
}
