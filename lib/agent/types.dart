// 公共类型定义
// 从 orbby-agent/src/types.ts 迁移

/// 工具定义
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema
  final Future<String> Function(Map<String, dynamic> args) execute;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });
}

/// 工具调用参数（传给 LLM 的格式，不含 execute）
class ToolCallDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolCallDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// 工具索引（用于延迟加载，只包含名称和描述）
class ToolIndex {
  final String name;
  final String description;

  const ToolIndex({
    required this.name,
    required this.description,
  });
}

/// LLM 返回的 tool_call
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// LLM 响应
class LLMResponse {
  final String role;
  final String? content;
  final String? reasoningContent;
  final List<ToolCall>? toolCalls;

  const LLMResponse({
    this.role = 'assistant',
    this.content,
    this.reasoningContent,
    this.toolCalls,
  });
}

/// OpenAI 消息格式
class Message {
  String role;
  String? content;
  List<ToolCallFunction>? toolCalls;
  String? toolCallId;

  Message({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'role': role,
    };
    if (content != null) {
      json['content'] = content;
    }
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      json['tool_calls'] = toolCalls!.map((tc) => tc.toJson()).toList();
    }
    if (toolCallId != null) {
      json['tool_call_id'] = toolCallId;
    }
    return json;
  }
}

/// 工具调用函数格式
class ToolCallFunction {
  final String id;
  final String type;
  final String name;
  final String arguments;

  const ToolCallFunction({
    required this.id,
    this.type = 'function',
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'function': {
      'name': name,
      'arguments': arguments,
    },
  };
}

/// LLM 配置
class LLMConfig {
  final String baseURL;
  final String apiKey;
  final String model;
  final String? compactModel;

  const LLMConfig({
    required this.baseURL,
    required this.apiKey,
    required this.model,
    this.compactModel,
  });
}

/// Agent 配置
class AgentConfig {
  final LLMConfig llm;
  final int maxContextTokens;
  final int keepRecentTurns;
  final int summaryMaxChars;
  final double contextSoftLimit;
  final double contextHardLimit;
  final int reservedOutputTokens;
  final int maxToolResultChars;
  final int maxIterations;

  const AgentConfig({
    required this.llm,
    this.maxContextTokens = 32000,
    this.keepRecentTurns = 3,
    this.summaryMaxChars = 2400,
    this.contextSoftLimit = 0.75,
    this.contextHardLimit = 0.90,
    this.reservedOutputTokens = 4096,
    this.maxToolResultChars = 12000,
    this.maxIterations = 10,
  });
}

/// Conversation 构造选项
class ConversationOptions {
  final int? maxTokens;
  final int? keepRecentTurns;
  final int? summaryMaxChars;
  final double? contextSoftLimit;
  final double? contextHardLimit;
  final int? reservedOutputTokens;
  final int? maxToolResultChars;

  const ConversationOptions({
    this.maxTokens,
    this.keepRecentTurns,
    this.summaryMaxChars,
    this.contextSoftLimit,
    this.contextHardLimit,
    this.reservedOutputTokens,
    this.maxToolResultChars,
  });
}

/// 压缩统计
class CompactionStats {
  final String reason;
  final int beforeTokens;
  final int afterTokens;
  final int removedMessages;
  final int summaryChars;

  const CompactionStats({
    required this.reason,
    required this.beforeTokens,
    required this.afterTokens,
    required this.removedMessages,
    required this.summaryChars,
  });

  @override
  String toString() =>
      'CompactionStats(reason: $reason, before: $beforeTokens, after: $afterTokens, removed: $removedMessages)';
}

/// 上下文状态
class ConversationStats {
  final int totalTokens;
  final int requestTokens;
  final int maxTokens;
  final int softLimit;
  final int hardLimit;
  final int usagePercent;
  final int messagesCount;
  final int summaryChars;
  final int totalCompacted;
  final int keepRecentTurns;
  final CompactionStats? lastCompaction;

  const ConversationStats({
    required this.totalTokens,
    required this.requestTokens,
    required this.maxTokens,
    required this.softLimit,
    required this.hardLimit,
    required this.usagePercent,
    required this.messagesCount,
    required this.summaryChars,
    required this.totalCompacted,
    required this.keepRecentTurns,
    this.lastCompaction,
  });
}

/// 压缩阈值
class CompactionThresholds {
  final int soft;
  final int hard;

  const CompactionThresholds({
    required this.soft,
    required this.hard,
  });
}
