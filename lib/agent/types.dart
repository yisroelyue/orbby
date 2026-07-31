// 公共类型定义
// 从 orbby-agent/src/types.ts 迁移，已 Dart 化（不可变 + copyWith）

/// 工具定义（含执行回调，不可用 freezed 生成）
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema
  final Future<String> Function(Map<String, dynamic> args) execute;
  final ToolExecutionMode executionMode;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
    this.executionMode = ToolExecutionMode.readOnly,
  });
}

enum ToolExecutionMode { readOnly, mutating }

class ToolResult {
  final bool success;
  final String output;
  final String? errorCode;
  final bool retryable;
  const ToolResult({
    required this.success,
    required this.output,
    this.errorCode,
    this.retryable = false,
  });
  factory ToolResult.ok(String output) =>
      ToolResult(success: true, output: output);
  factory ToolResult.error(
    String output, {
    String? code,
    bool retryable = false,
  }) => ToolResult(
    success: false,
    output: output,
    errorCode: code,
    retryable: retryable,
  );
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

  ToolCallDefinition copyWith({
    String? name,
    String? description,
    Map<String, dynamic>? parameters,
  }) => ToolCallDefinition(
    name: name ?? this.name,
    description: description ?? this.description,
    parameters: parameters ?? this.parameters,
  );

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

  const ToolIndex({required this.name, required this.description});

  ToolIndex copyWith({String? name, String? description}) => ToolIndex(
    name: name ?? this.name,
    description: description ?? this.description,
  );
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

  ToolCall copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? arguments,
  }) => ToolCall(
    id: id ?? this.id,
    name: name ?? this.name,
    arguments: arguments ?? this.arguments,
  );
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

  LLMResponse copyWith({
    String? role,
    String? content,
    String? reasoningContent,
    List<ToolCall>? toolCalls,
  }) => LLMResponse(
    role: role ?? this.role,
    content: content ?? this.content,
    reasoningContent: reasoningContent ?? this.reasoningContent,
    toolCalls: toolCalls ?? this.toolCalls,
  );
}

/// OpenAI 消息格式（不可变）
class Message {
  final String role;
  final String? content;
  final List<ToolCallFunction>? toolCalls;
  final String? toolCallId;

  const Message({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
  });

  Message copyWith({
    String? role,
    String? content,
    List<ToolCallFunction>? toolCalls,
    String? toolCallId,
  }) => Message(
    role: role ?? this.role,
    content: content ?? this.content,
    toolCalls: toolCalls ?? this.toolCalls,
    toolCallId: toolCallId ?? this.toolCallId,
  );

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'role': role};
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

  ToolCallFunction copyWith({
    String? id,
    String? type,
    String? name,
    String? arguments,
  }) => ToolCallFunction(
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    arguments: arguments ?? this.arguments,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'function': {'name': name, 'arguments': arguments},
  };
}

/// Conversation 构造选项
class ConversationOptions {
  final int maxTokens;
  final int keepRecentTurns;
  final int summaryMaxChars;
  final double contextSoftLimit;
  final double contextHardLimit;
  final int reservedOutputTokens;
  final int maxToolResultChars;

  const ConversationOptions({
    this.maxTokens = 32000,
    this.keepRecentTurns = 3,
    this.summaryMaxChars = 2400,
    this.contextSoftLimit = 0.75,
    this.contextHardLimit = 0.90,
    this.reservedOutputTokens = 4096,
    this.maxToolResultChars = 12000,
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

  @override
  String toString() =>
      'ConversationStats(tokens: $totalTokens/$maxTokens [$usagePercent%], messages: $messagesCount, compacted: $totalCompacted)';
}

/// 压缩阈值
class CompactionThresholds {
  final int soft;
  final int hard;

  const CompactionThresholds({required this.soft, required this.hard});

  @override
  String toString() => 'CompactionThresholds(soft: $soft, hard: $hard)';
}
