// Conversation history, token budgeting, and safe context compaction.
// 从 orbby-agent/src/conversation.ts 迁移

import 'dart:convert';
import 'dart:io';

import 'types.dart';

/// 默认系统提示
String _defaultSystemPrompt() {
  final homeDir =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final cwd = Directory.current.path;
  return '你是一个能通过调用工具完成任务的 AI 助手。\n'
      '你的工作方式：理解需求，调用工具执行，返回结果\n'
      '- 当前系统: ${Platform.operatingSystem}，用户主目录: $homeDir\n'
      '- 当前工作目录: $cwd';
}

/// 回合块（用于安全压缩）
class _TurnBlock {
  final List<Message> messages;
  final bool complete;

  _TurnBlock({required this.messages, required this.complete});
}

/// 对话管理、token 预算、安全上下文压缩
class Conversation {
  final int maxTokens;
  final int keepRecentTurns;
  final int summaryMaxChars;
  final int maxToolResultChars;
  final double contextSoftLimit;
  final double contextHardLimit;
  final int reservedOutputTokens;

  List<Message> messages = [];
  String summary = '';
  int totalCompacted = 0;
  CompactionStats? lastCompaction;

  Conversation({ConversationOptions? options, String? systemPrompt})
    : maxTokens = options?.maxTokens ?? 32000,
      keepRecentTurns = options?.keepRecentTurns ?? 3,
      summaryMaxChars = options?.summaryMaxChars ?? 2400,
      maxToolResultChars = options?.maxToolResultChars ?? 12000,
      contextSoftLimit = options?.contextSoftLimit ?? 0.75,
      contextHardLimit = options?.contextHardLimit ?? 0.90,
      reservedOutputTokens = options?.reservedOutputTokens ?? 4096 {
    messages.add(
      Message(role: 'system', content: systemPrompt ?? _defaultSystemPrompt()),
    );
  }

  /// 粗略 token 估算（字符数 / 4）
  int _estimateTokens(String? text) {
    if (text == null || text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  /// 单条消息的 token 估算
  int _messageTokens(Message msg) {
    var text = '';
    if (msg.content != null) text += msg.content!;
    if (msg.toolCalls != null) {
      for (final tc in msg.toolCalls!) {
        text += tc.id;
        text += tc.name;
        text += tc.arguments;
      }
    }
    if (msg.toolCallId != null) text += msg.toolCallId!;
    return _estimateTokens(text);
  }

  /// 当前消息的总 token 数
  int totalTokens() {
    return messages.fold(0, (sum, msg) => sum + _messageTokens(msg));
  }

  /// 估算请求 token 数（消息 + 工具定义 + 预留输出）
  int estimateRequestTokens(List<ToolCallDefinition>? tools) {
    final messageTokens = totalTokens();
    final toolTokens = tools != null ? _estimateTokens(_toolsToJson(tools)) : 0;
    return messageTokens + toolTokens + reservedOutputTokens;
  }

  /// 获取压缩阈值
  CompactionThresholds getCompactionThresholds() {
    return CompactionThresholds(
      soft: (maxTokens * contextSoftLimit).floor(),
      hard: (maxTokens * contextHardLimit).floor(),
    );
  }

  /// 使用百分比
  int usagePercent([int? requestTokens]) {
    final tokens = requestTokens ?? totalTokens();
    return ((tokens / maxTokens) * 100).round();
  }

  /// 添加用户消息
  void addUserMessage(String content) {
    messages.add(Message(role: 'user', content: content));
  }

  /// 序列化单条消息为文本格式（用于摘要生成）
  String _serializeMessage(Message msg) {
    switch (msg.role) {
      case 'user':
        return '[User]: ${msg.content ?? ''}';
      case 'assistant':
        var text = '[Assistant]: ${msg.content ?? ''}';
        if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
          text +=
              '\n[Tool Calls]: ${msg.toolCalls!.map((tc) => '${tc.name}(${tc.arguments})').join(', ')}';
        }
        return text;
      case 'tool':
        return '[Tool Result]: ${msg.content ?? ''}';
      default:
        return '[${msg.role}]: ${msg.content ?? ''}';
    }
  }

  /// 序列化消息列表为对话文本（用于摘要生成）
  String _serializeConversation(List<Message> messages) {
    return messages.map((msg) => _serializeMessage(msg)).join('\n\n');
  }

  /// 提取文件操作（读取/修改的文件）
  /// 通过工具名模式匹配而非硬编码具体名称：
  /// - 包含 "read" 的工具视为读取
  /// - 包含 "write"/"create"/"edit"/"delete" 的工具视为修改
  Map<String, Set<String>> _extractFileOperations(List<Message> messages) {
    final readFiles = <String>{};
    final modifiedFiles = <String>{};

    for (final msg in messages) {
      if (msg.role == 'assistant' && msg.toolCalls != null) {
        for (final call in msg.toolCalls!) {
          try {
            final args = _parseArguments(call.arguments);
            final path = args['path'] as String?;
            if (path == null || path.isEmpty) continue;

            final name = call.name.toLowerCase();
            if (name.contains('read')) {
              readFiles.add(path);
            } else if (name.contains('write') ||
                name.contains('create') ||
                name.contains('edit') ||
                name.contains('delete')) {
              modifiedFiles.add(path);
            }
          } catch (_) {
            // 忽略解析错误
          }
        }
      }
    }

    return {'readFiles': readFiles, 'modifiedFiles': modifiedFiles};
  }

  /// 添加助手消息
  void addAssistantMessage(LLMResponse response) {
    messages.add(
      Message(
        role: 'assistant',
        content: response.content,
        toolCalls: response.toolCalls
            ?.map(
              (tc) => ToolCallFunction(
                id: tc.id,
                name: tc.name,
                arguments: _encodeArguments(tc.arguments),
              ),
            )
            .toList(),
      ),
    );
  }

  /// 截断工具结果
  String _trimToolResult(dynamic result) {
    final text = result is String ? result : '$result';
    if (text.length <= maxToolResultChars) return text;
    final head = (maxToolResultChars * 0.7).floor();
    final tail = maxToolResultChars - head;
    return '${text.substring(0, head)}\n\n[工具输出已截断，原始长度 ${text.length} 字符]\n\n${text.substring(text.length - tail)}';
  }

  /// 添加工具结果
  void addToolResult(String toolCallId, dynamic result) {
    messages.add(
      Message(
        role: 'tool',
        toolCallId: toolCallId,
        content: _trimToolResult(result),
      ),
    );
  }

  /// 获取消息列表
  List<Message> getMessages() => List.unmodifiable(messages);

  /// 获取摘要
  String getSummary() => summary;

  /// 重置对话
  void reset() {
    messages = [messages.first]; // 保留系统提示
    summary = '';
    totalCompacted = 0;
    lastCompaction = null;
  }

  /// 将消息按回合分组
  List<_TurnBlock> _getTurnBlocks() {
    final blocks = <_TurnBlock>[];
    var current = <Message>[];

    for (final message in messages.skip(1)) {
      if (message.role == 'user' && current.isNotEmpty) {
        blocks.add(
          _TurnBlock(
            messages: current,
            complete: current.any(
              (m) => m.role == 'assistant' && m.toolCalls == null,
            ),
          ),
        );
        current = [];
      }
      current.add(message);
      if (message.role == 'assistant' &&
          message.toolCalls == null &&
          current.isNotEmpty) {
        blocks.add(_TurnBlock(messages: current, complete: true));
        current = [];
      }
    }

    if (current.isNotEmpty) {
      blocks.add(_TurnBlock(messages: current, complete: false));
    }

    return blocks;
  }

  /// 找到安全裁剪点
  ({List<_TurnBlock> blocks, int removeCount})? _findSafeTrimPoint(
    int keepTurns,
  ) {
    final blocks = _getTurnBlocks();
    final complete = blocks.where((block) => block.complete).toList();
    if (complete.length <= keepTurns) return null;

    final keep = Set.from(complete.skip(complete.length - keepTurns));
    var removeCount = 0;

    for (final block in blocks) {
      if (keep.contains(block)) break;
      if (!block.complete) return null;
      removeCount += block.messages.length;
    }

    return (blocks: blocks, removeCount: removeCount);
  }

  /// 限制摘要长度
  String _limitSummary(String summary) {
    if (summary.isEmpty) return '';
    if (summary.length <= summaryMaxChars) return summary;
    return '${summary.substring(0, summaryMaxChars - 80)}\n[摘要已按长度限制截断]';
  }

  /// 检查是否需要压缩，执行压缩
  Future<bool> maybeCompact(
    Future<String> Function(
      List<Message> oldMessages,
      String existingSummary,
      String serializedConversation,
      Map<String, Set<String>> fileOps,
    )?
    summarizeFn, {
    int? requestTokens,
    bool force = false,
    String reason = 'soft_limit',
  }) async {
    final currentRequestTokens = requestTokens ?? totalTokens();
    final thresholds = getCompactionThresholds();
    final shouldCompact = force || currentRequestTokens > thresholds.soft;
    if (!shouldCompact) return false;

    final keepTurns = currentRequestTokens > thresholds.hard
        ? 1
        : keepRecentTurns;
    final safePoint = _findSafeTrimPoint(keepTurns);
    if (safePoint == null || safePoint.removeCount == 0) return false;

    // 提取待压缩的旧消息
    final completeBlocks = safePoint.blocks.where((b) => b.complete).toList();
    final blocksToCompact = completeBlocks
        .take(completeBlocks.length - keepTurns)
        .toList();
    final oldMessages = blocksToCompact.expand((b) => b.messages).toList();
    final recentMessages = messages.skip(1).skip(oldMessages.length).toList();

    var newSummary = summary;

    if (summarizeFn != null && oldMessages.isNotEmpty) {
      try {
        // 序列化对话用于摘要生成
        final serializedConversation = _serializeConversation(oldMessages);
        // 提取文件操作
        final fileOps = _extractFileOperations(oldMessages);

        newSummary = _limitSummary(
          await summarizeFn(
            oldMessages,
            summary,
            serializedConversation,
            fileOps,
          ),
        );
      } catch (_) {
        // 摘要生成失败，保留原有历史
        return false;
      }
      if (newSummary.isEmpty) return false;
    }

    final beforeTokens = totalTokens();
    final systemMsg = messages.first;
    final rebuilt = <Message>[systemMsg];

    if (newSummary.isNotEmpty) {
      rebuilt.add(
        Message(
          role: 'system',
          content: '[上下文任务状态]\n$newSummary\n---\n以上内容是历史任务状态，请以此为背景继续处理后续请求。',
        ),
      );
    }

    rebuilt.addAll(recentMessages);
    summary = newSummary;
    messages = rebuilt;
    totalCompacted++;
    lastCompaction = CompactionStats(
      reason: reason,
      beforeTokens: beforeTokens,
      afterTokens: totalTokens(),
      removedMessages: oldMessages.length,
      summaryChars: summary.length,
    );

    return true;
  }

  /// 获取上下文状态
  ConversationStats stats([int? requestTokens]) {
    final thresholds = getCompactionThresholds();
    final currentRequestTokens = requestTokens ?? totalTokens();
    return ConversationStats(
      totalTokens: totalTokens(),
      requestTokens: currentRequestTokens,
      maxTokens: maxTokens,
      softLimit: thresholds.soft,
      hardLimit: thresholds.hard,
      usagePercent: usagePercent(currentRequestTokens),
      messagesCount: messages.length,
      summaryChars: summary.length,
      totalCompacted: totalCompacted,
      keepRecentTurns: keepRecentTurns,
      lastCompaction: lastCompaction,
    );
  }

  /// 将工具定义列表转为 JSON 字符串（用于 token 估算）
  String _toolsToJson(List<ToolCallDefinition> tools) {
    return '[${tools.map((t) => '{"name":"${t.name}","description":"${t.description}"}').join(',')}]';
  }

  /// 解析 JSON 字符串参数
  Map<String, dynamic> _parseArguments(String args) {
    try {
      if (args.isEmpty) return {};
      final decoded = jsonDecode(args);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  /// 编码参数为 JSON 字符串
  String _encodeArguments(Map<String, dynamic> args) {
    try {
      return jsonEncode(args);
    } catch (_) {
      return '{}';
    }
  }
}
