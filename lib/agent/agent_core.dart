// Agent 核心循环（ReAct 模式）
// 从 orbby-agent/src/agent.ts 迁移
// 将用户输入发给 LLM，LLM 决定是回复文本还是调用工具
// 如果调用工具，执行后将结果喂回 LLM，循环直到 LLM 返回文本

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'conversation.dart';
import 'llm_client.dart';
import 'tool_registry.dart';
import 'types.dart';

/// Agent 核心类
class Agent {
  final Conversation conversation;
  final LLMClient llm;
  final ToolRegistry registry;
  final int maxIterations;

  /// 核心工具（始终提供给 LLM）
  final List<String> coreToolNames;

  /// 延迟加载工具索引
  List<ToolIndex> toolIndex = [];

  /// search_tools 虚拟工具定义
  ToolCallDefinition? toolSearchDefinition;

  /// search_tools 工具名称
  final String toolSearchName = 'search_tools';

  Agent({
    required this.llm,
    required this.registry,
    ConversationOptions? conversationOptions,
    String? systemPrompt,
    this.maxIterations = 10,
    List<String>? coreToolNames,
  }) : conversation = Conversation(
         options: conversationOptions,
         systemPrompt: systemPrompt,
       ),
       coreToolNames =
           coreToolNames ??
           ['search_files', 'read_file', 'edit_file', 'execute_command'];

  /// 初始化 Agent（构建工具索引和 search_tools 定义）
  void init() {
    // 获取非核心工具的轻量索引
    toolIndex = registry.getToolIndex(excludeNames: coreToolNames);

    // 构建工具索引文本
    final indexText = toolIndex.isNotEmpty
        ? toolIndex
              .map((tool) => '- ${tool.name}: ${tool.description}')
              .join('\n')
        : '(暂无其他工具)';

    // 构建 search_tools 虚拟工具定义
    toolSearchDefinition = ToolCallDefinition(
      name: toolSearchName,
      description:
          '搜索并加载未直接提供的工具。只有当当前已提供的工具无法完成任务时才调用。'
          '请根据用户任务填写 query；搜索成功后，匹配工具的完整参数定义会在下一轮请求中提供。'
          '\n可延迟加载工具索引：\n$indexText',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '要完成的任务或需要的能力，例如"删除文件""打开浏览器"',
          },
        },
        'required': ['query'],
      },
    );
  }

  /// 生成结构化上下文摘要（优先用轻量压缩模型，失败则回退主力模型）
  Future<String> generateSummary(
    List<Message> oldMessages,
    String existingSummary,
    String serializedConversation,
    Map<String, Set<String>> fileOps,
  ) async {
    const systemPrompt = '''你是对话摘要助手。严格按照指定格式输出摘要，不要加任何额外说明。

输出格式：
## Goal
[用户要完成什么任务？]

## Constraints & Preferences
- [用户提到的约束条件]
- 或 "(none)" 如果没有

## Progress
### Done
- [x] [已完成的任务/修改]

### In Progress
- [ ] [当前进行中的工作]

### Blocked
- [阻碍进展的问题，没有则省略此节]

## Key Decisions
- **[决策]**: [简要理由]
- 没有则输出 "(none)"

## Next Steps
1. [下一步应该做什么]

## Critical Context
- [需要的关键数据、示例或引用]

## File Operations
### Read
- [读取的文件路径]
### Modified
- [修改的文件路径]

重要规则：
- 文件路径、命令、错误信息和未完成事项优先保留
- 可通过工具重新读取的大段文件内容不要原样复制
- 不要编造信息
- File Operations 部分根据实际传入的文件操作数据填写，没有则省略''';

    // 构建用户提示
    String userPrompt;

    if (existingSummary.isNotEmpty) {
      // 增量更新
      userPrompt =
          '''请将以下新对话合并到已有的上下文摘要中。

## 已有摘要
$existingSummary

## 新对话内容
$serializedConversation

请输出更新后的完整摘要，保留已有信息并添加新进展。''';
    } else {
      // 首次生成
      userPrompt = '''请将以下对话历史压缩为结构化上下文摘要。

## 对话内容
$serializedConversation''';
    }

    // 如果有文件操作数据，追加到用户提示末尾
    if (fileOps.isNotEmpty &&
        (fileOps['readFiles']?.isNotEmpty == true ||
            fileOps['modifiedFiles']?.isNotEmpty == true)) {
      userPrompt += '\n\n## 文件操作数据\n';
      if (fileOps['readFiles']?.isNotEmpty == true) {
        userPrompt += '读取的文件：\n';
        for (final f in fileOps['readFiles']!) {
          userPrompt += '- $f\n';
        }
      }
      if (fileOps['modifiedFiles']?.isNotEmpty == true) {
        userPrompt += '修改的文件：\n';
        for (final f in fileOps['modifiedFiles']!) {
          userPrompt += '- $f\n';
        }
      }
    }

    try {
      final result = await llm.chat([
        Message(role: 'system', content: systemPrompt),
        Message(role: 'user', content: userPrompt),
      ]);
      return result.content ?? '';
    } catch (err) {
      // 轻量模型失败，回退到主力模型
      debugPrint('[Agent] 摘要生成失败 ($err)，返回已有摘要');
      return existingSummary;
    }
  }

  /// 处理用户输入，返回 Agent 回复
  Future<String> processMessage(
    String userInput, {
    void Function(String token)? onToken,
  }) async {
    // 特殊命令
    if (userInput == '/reset') {
      conversation.reset();
      return '对话已重置。';
    }

    if (userInput == '/tools') {
      final tools = registry.getToolDefinitions();
      return '可用工具:\n${tools.map((t) => '  - ${t.name}: ${t.description}').join('\n')}';
    }

    if (userInput == '/compact') {
      return await handleCompact();
    }

    if (userInput == '/stats') {
      return handleStats();
    }

    // 添加用户消息
    conversation.addUserMessage(userInput);

    // 添加用户消息后检查 token 是否超限
    await conversation.maybeCompact(
      (oldMessages, existingSummary, serializedConversation, fileOps) =>
          generateSummary(
            oldMessages,
            existingSummary,
            serializedConversation,
            fileOps,
          ),
      requestTokens: conversation.totalTokens(),
      reason: 'before_request',
    );

    // 只发送核心工具和 search_tools；其他工具由模型按需搜索后延迟加载
    final loadedToolNames = Set<String>.from(coreToolNames);
    var tools = _getActiveToolDefinitions(loadedToolNames);

    // ReAct 循环
    var iteration = 0;
    while (iteration < maxIterations) {
      iteration++;

      await conversation.maybeCompact(
        (oldMessages, existingSummary, serializedConversation, fileOps) =>
            generateSummary(
              oldMessages,
              existingSummary,
              serializedConversation,
              fileOps,
            ),
        requestTokens: conversation.estimateRequestTokens(tools),
        reason: 'before_request',
      );

      final requestTokens = conversation.estimateRequestTokens(tools);
      if (requestTokens > conversation.getCompactionThresholds().hard) {
        return '当前上下文仍然过大，且无法安全压缩。请先使用 /compact，或将任务拆分后继续。';
      }

      final messages = conversation.getMessages();

      // 调用 LLM（流式）
      final response = await llm.chatStream(
        messages,
        tools: tools,
        onToken: onToken,
      );

      // 纯文本回复（任务完成）
      if (response.toolCalls == null || response.toolCalls!.isEmpty) {
        conversation.addAssistantMessage(response);
        return response.content ?? '抱歉，我没有理解你的意思，可以换个方式再说一次吗？';
      }

      // 有工具调用：执行并将结果喂回 LLM
      conversation.addAssistantMessage(response);

      for (final toolCall in response.toolCalls!) {
        debugPrint(
          '  调用工具: ${toolCall.name}(${jsonEncode(toolCall.arguments)})',
        );

        String result;
        if (toolCall.name == toolSearchName) {
          result = _loadToolsForQuery(toolCall.arguments, loadedToolNames);
          tools = _getActiveToolDefinitions(loadedToolNames);
        } else {
          result = (await registry.executeTool(
            toolCall.name,
            toolCall.arguments,
          )).output;
        }

        debugPrint('  工具结果: $result');
        conversation.addToolResult(toolCall.id, result);
      }

      // 工具执行后检查 token 是否超限
      await conversation.maybeCompact(
        (oldMessages, existingSummary, serializedConversation, fileOps) =>
            generateSummary(
              oldMessages,
              existingSummary,
              serializedConversation,
              fileOps,
            ),
        requestTokens: conversation.estimateRequestTokens(tools),
        reason: 'after_tool_result',
      );

      continue;
    }

    // 达到最大循环次数
    return '抱歉，任务步骤太多，超过了处理限制。请尝试将任务拆分成更小的步骤。';
  }

  /// 获取当前活跃的工具定义
  List<ToolCallDefinition> _getActiveToolDefinitions(
    Set<String> loadedToolNames,
  ) {
    final definitions = registry.getToolDefinitionsByNames(
      loadedToolNames.toList(),
    );
    if (toolSearchDefinition != null && toolIndex.isNotEmpty) {
      definitions.add(toolSearchDefinition!);
    }
    return definitions;
  }

  /// 延迟加载工具
  String _loadToolsForQuery(
    Map<String, dynamic> args,
    Set<String> loadedToolNames,
  ) {
    final query = (args['query'] as String?)?.trim().toLowerCase() ?? '';
    if (query.isEmpty) {
      return '工具搜索失败：query 不能为空。可搜索的工具：\n'
          '${toolIndex.map((tool) => '- ${tool.name}: ${tool.description}').join('\n')}';
    }

    // 分词（支持中文二元组）
    final terms = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).expand(
      (term) {
        final chinese = RegExp(
          r'[一-鿿]',
        ).allMatches(term).map((m) => m.group(0)!).toList();
        if (chinese.length < 2) return [term];
        final chunks = <String>[];
        for (var i = 0; i < chinese.length - 1; i++) {
          chunks.add(chinese.sublist(i, i + 2).join());
        }
        return [term, ...chunks];
      },
    ).toList();

    // 搜索匹配
    final matches =
        toolIndex
            .map((tool) {
              final text = '${tool.name} ${tool.description}'.toLowerCase();
              final score = terms.fold(
                0,
                (total, term) => total + (text.contains(term) ? 1 : 0),
              );
              return (tool: tool, score: score);
            })
            .where((item) => item.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    final topMatches = matches.take(3).map((item) => item.tool).toList();

    if (topMatches.isEmpty) {
      return '未找到与"$query"匹配的工具。可用工具索引：\n'
          '${toolIndex.map((tool) => '- ${tool.name}: ${tool.description}').join('\n')}';
    }

    for (final tool in topMatches) {
      loadedToolNames.add(tool.name);
    }
    return '已加载以下工具的完整定义，下一轮可以调用：\n'
        '${topMatches.map((tool) => '- ${tool.name}: ${tool.description}').join('\n')}';
  }

  /// 处理 /compact 命令：手动触发上下文压缩
  Future<String> handleCompact() async {
    final beforeTokens = conversation.totalTokens();
    final wasCompacted = await conversation.maybeCompact(
      (oldMessages, existingSummary, serializedConversation, fileOps) =>
          generateSummary(
            oldMessages,
            existingSummary,
            serializedConversation,
            fileOps,
          ),
      force: true,
      reason: 'manual',
    );

    if (wasCompacted) {
      final afterTokens = conversation.totalTokens();
      final saved = beforeTokens - afterTokens;
      final summaryPreview = conversation.summary.length > 200
          ? '${conversation.summary.substring(0, 200)}...'
          : conversation.summary;
      return '上下文已压缩。\n压缩前: $beforeTokens tokens → 压缩后: $afterTokens tokens (释放 $saved tokens)\n摘要: $summaryPreview';
    } else {
      return '上下文使用率 ${conversation.usagePercent()}%，未达到压缩阈值（上限 ${conversation.maxTokens} tokens），无需压缩。';
    }
  }

  /// 处理 /stats 命令：查看上下文状态
  String handleStats() {
    final stats = conversation.stats();
    return [
      '── 上下文状态 ──',
      '消息数: ${stats.messagesCount}',
      'Token 估算: ${stats.totalTokens} / ${stats.maxTokens} (${stats.usagePercent}%)',
      '已压缩次数: ${stats.totalCompacted}',
      '当前摘要长度: ${stats.summaryChars} 字符',
      '保留最近回合: ${stats.keepRecentTurns}',
      '主力模型: ${llm.model}',
    ].join('\n');
  }
}
