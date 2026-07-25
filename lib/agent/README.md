# Agent 核心模块

从 `orbby-agent` (TypeScript) 项目迁移的 Agent 核心系统，支持工具调用和上下文管理。

## 模块结构

```
lib/agent/
├── agent.dart              # 模块导出
├── agent_core.dart         # Agent 核心循环（ReAct 模式）
├── conversation.dart       # 上下文管理（token 预算、压缩）
├── llm_client.dart         # LLM 调用封装（支持 tool_calls）
├── tool_registry.dart      # 工具注册中心
├── types.dart              # 类型定义
└── tools/
    └── builtin_tools.dart  # 内置工具定义
```

## 核心功能

### 1. ReAct 循环
Agent 采用 ReAct（Reasoning + Acting）模式：
- 接收用户输入
- LLM 决定是直接回复还是调用工具
- 如果调用工具，执行后将结果喂回 LLM
- 循环直到 LLM 返回文本回复

### 2. 工具系统
- **ToolRegistry**: 工具注册中心，管理所有可用工具
- **延迟加载**: 核心工具始终提供，非核心工具通过 `search_tools` 按需加载
- **内置工具**: 待办事项、收藏、剪贴板、系统时间等

### 3. 上下文管理
- **Token 预算**: 粗略估算（字符数 / 4）
- **安全压缩**: 按回合边界裁剪，不会在工具调用中间截断
- **结构化摘要**: Goal / Progress / Next Steps 等标准字段
- **双模型架构**: 主力模型处理任务，轻量模型做摘要压缩

## 使用方式

### 方式 1: 使用 AgentServiceV2（推荐）

```dart
import 'services/agent_service_v2.dart';

// 非流式调用
final response = await AgentServiceV2.chat('帮我创建一个待办事项');

// 流式调用
AgentServiceV2.chatStream('帮我搜索收藏').listen((token) {
  print(token);
});

// 重置对话
AgentServiceV2.resetConversation();

// 获取对话状态
final stats = AgentServiceV2.getConversationStats();

// 手动压缩上下文
await AgentServiceV2.compact();
```

### 方式 2: 直接使用 Agent 类

```dart
import 'agent/agent_core.dart';
import 'agent/llm_client.dart';
import 'agent/tool_registry.dart';
import 'agent/tools/builtin_tools.dart';

// 创建 LLM 客户端
final llm = LLMClient(
  baseURL: 'https://api.deepseek.com/v1/chat/completions',
  apiKey: 'your-api-key',
  model: 'deepseek-chat',
);

// 创建压缩模型客户端
final compactLLM = LLMClient(
  baseURL: 'https://api.deepseek.com/v1/chat/completions',
  apiKey: 'your-api-key',
  model: 'deepseek-chat', // 或使用更轻量的模型
);

// 创建工具注册中心
final registry = ToolRegistry();
registerBuiltinTools(registry);

// 创建 Agent
final agent = Agent(
  llm: llm,
  compactLLM: compactLLM,
  registry: registry,
);

// 初始化
agent.init();

// 处理消息
final response = await agent.processMessage('帮我创建一个待办事项');

// 流式处理
await agent.processMessage(
  '帮我搜索收藏',
  onToken: (token) => print(token),
);
```

### 方式 3: 自定义工具

```dart
import 'agent/types.dart';
import 'agent/tool_registry.dart';

// 定义自定义工具
final customTool = ToolDefinition(
  name: 'my_tool',
  description: '我的自定义工具',
  parameters: {
    'type': 'object',
    'properties': {
      'input': {
        'type': 'string',
        'description': '输入参数',
      },
    },
    'required': ['input'],
  },
  execute: (args) async {
    final input = args['input'] as String;
    return '处理结果: $input';
  },
);

// 注册工具
final registry = ToolRegistry();
registry.register(customTool);
```

## 特殊命令

Agent 支持以下特殊命令：

- `/reset` - 重置对话
- `/tools` - 列出所有可用工具
- `/compact` - 手动触发上下文压缩
- `/stats` - 查看上下文状态

## 配置说明

### 上下文配置

```dart
final agent = Agent(
  llm: llm,
  compactLLM: compactLLM,
  registry: registry,
  conversationOptions: ConversationOptions(
    maxTokens: 32000,           // 最大 token 数
    keepRecentTurns: 3,         // 压缩时保留最近 N 个回合
    summaryMaxChars: 2400,      // 摘要最大字符数
    maxToolResultChars: 12000,  // 工具结果最大字符数
    contextSoftLimit: 0.75,     // 软限制（触发压缩）
    contextHardLimit: 0.90,     // 硬限制（强制压缩）
    reservedOutputTokens: 4096, // 预留输出 token
  ),
  maxIterations: 10,            // 最大循环次数
  coreToolNames: ['search_files', 'read_file', 'edit_file', 'execute_command'],
);
```

## 与原项目的差异

| 功能 | 原项目 (TypeScript) | 迁移后 (Flutter) |
|------|---------------------|------------------|
| 工具注册 | 动态扫描目录 | 静态注册 |
| WebSocket | 支持 | 移除 |
| 控制台输出 | 支持 | 移除（使用 debugPrint） |
| CLI 入口 | 支持 | 移除 |
| 多平台 API | 支持 | 保留（复用 PlatformConfig） |

## 下一步

1. 实现内置工具的具体逻辑（调用现有服务）
2. 在 AgentChatPopup 中集成 AgentServiceV2
3. 添加更多自定义工具
4. 优化流式输出体验
