# 项目规范
- 不进行flutter分析，测试，会卡住，改完代码告诉我就可以。
- 影响当前架构的改动需要告诉我，改动完了之后更新规范文件。
- 考虑所有情况，不合适就给我说这个想法不合适，而不是迎合我，头疼医头。
- 不要执行flutter分析
- 保持架构清晰，严禁过度耦合，合理拆分代码模块。
- 考虑扩展性，每次改动不能只考虑完成当前需求

## 架构

- Flutter Windows 多窗口应用，**每个窗口是独立 Flutter engine，静态变量/单例不跨窗口共享**——跨窗口必须走 channel 或 AppEvents。
- 入口 `lib/main.dart` 按启动参数 `type` 分发各窗口 UI 与窗口配置。主窗口（pet）常驻隐藏，跑 `WindowCoordinator`（`lib/services/window_coordinator.dart`，即 hub）：全局快捷键 + 所有子窗口的创建/定位/显示。
- 子窗口：`menu`（聊天 HomeScreen）、`settings`、`app_bar`、`content`、`app_center`、`about`。menu/settings 启动时预创建（hiddenAtLaunch），常驻窗口用 hide/show 切换；app_center/about 每次新建。
- 窗口通信（本地 fork 的 `packages/desktop_multi_window`）两条路：
  - `WindowMethodChannel(..., ChannelMode.unidirectional)`：全局仅 hub 注册 handler，任何 engine 都能 invoke → **子→hub**（ready、hidden、open_settings 等）。
  - `window.invokeMethod(...)` 定向调用子窗口的 `setWindowMethodHandler` → **hub→子**（place、app_event 等）。
- **ready 握手**：子窗口 engine 就绪后发 `'ready'`，hub 等 Completer（5s 超时兜底）再 place/show；不等的话首次 place 会丢。

## Agent 流式协议

- Agent Runtime 未设置 `ORBBY_WORKSPACE` 时，初始工作区默认为当前用户的桌面目录；显式设置 `ORBBY_WORKSPACE` 时优先使用该目录。

- Agent 的 ReAct 工具循环运行在 `agent-runtime/` Node.js 子进程中，通过 localhost WebSocket 与 Flutter 通信。每轮文本经 `agent.token` 流式发出，工具循环最多 30 个 step；Flutter 的 `AgentService.chatStream` 继续转换为 `AgentTokenEvent`/`AgentRoundEvent`，Dart 侧不再运行 Agent 核心。
- **流式契约：processMessage 正常完成时返回值 = 最后一轮已流出的 content，chatStream 对已流出过 token 的会话只关流不补发返回值（防整段重复）。因此 processMessage 内所有"额外兜底文案"（超轮次/上下文超硬限/空回复）必须自行经 `onToken` 发出再 return，否则 UI 会在已有文字后静默收尾，看起来像卡死。**
- HomeScreen 收到 `AgentRoundEvent` 时在气泡内插 `\n\n---\n\n` 分隔轮次；该拼接文本随会话落盘、也作为 history 发回 LLM。**新增事件类型（如工具调用进度）时扩展 AgentStreamEvent 子类 + 各消费方 switch**，不要回退成裸字符串流（多轮文字会粘成一坨）。
- `lib/agent/llm_client.dart` 的 HTTP 层收敛为公共骨架，**新增 LLM provider 复用骨架，勿再复制重试/超时逻辑**：`_withRetry`（统一重试+退避，`retryable` 回调供流式路径拦截"已流出内容"的重试，防 UI 文本重复）+ `_post`（连接/首字节超时、client 生命周期）+ `_readBody`/`_sseLines`（响应体读取超时：SSE 空闲 60s 每行重置、非流式整体 120s）。四个 `_call*` 方法只留协议差异（headers、body 组装 `_compatibleBody`/`_anthropicBody`、解析 `_parse*`），超时常量集中在类顶部。
- **用户提问（ask_user_question / 目录权限确认）**：问题结构化 `AgentQuestion`（question/header/type(choice|text)/options/multiSelect，契约定义在 `agent-runtime/src/protocol.ts`，Flutter 侧模型在 `lib/models/agent_question.dart`，两端字段一致）；`user.answer` payload 为 `answers: string[][]`（按问题索引对应，空数组=跳过）。挂起的提问 promise 存在 **per-connection** 的 answers Map（value 含 requestId/resolve/reject）：**chat.cancel 与 socket close 必须 reject 挂起问题**，否则工具 worker 卡死并经 runExclusive 锁死整个会话。目录权限确认（workspace-permission）复用同一通道，答案按 `answers[0][0] === '允许'` 精确匹配（勿回退成字符串包含匹配）。

## HomeScreen 文件拆分

聊天主窗口 HomeScreen 位于 `lib/screens/home_screen/`，按功能拆成 part 文件（`part of 'home_screen.dart'`，同库可互访私有成员），主文件只留骨架：

- `home_screen.dart`：`HomeScreen`/`_HomeScreenState`、可变状态字段、initState/dispose/生命周期、MaterialApp 骨架 `build`，以及库级视觉常量（颜色/字体/Theme 提为顶层常量，extension 内直接裸名引用）。
- `commands.dart`：`_buildCommands()` 命令注册表 + `/setting` 的 Agent 设置弹窗。**新增命令只在这里注册，具体逻辑必须调用独立处理方法，不得内联业务代码**。
- `command_actions.dart`：命令具体动作实现（通过 extension 挂回 `_HomeScreenState`）；命令数量增长时继续在此按领域拆分。
- `input.dart`：输入框 UI、输入历史（↑/↓ 浏览/草稿恢复）、命令面板确认 `_confirmCommand`、键盘导航接管 `_handleKeyEvent`。
- `conversation.dart`：会话保存 `_saveConversation`（`_saveChain` 串行链）、本地消息 `_addLocalMessage`、会话切换/复制、落盘 JSON 解码还原。
- `agent.dart`：`_sendMessage`/`_sendText`（chatStream 消费与事件分发）、`_runCompact`、提问卡片的提交/跳过/收起。
- `messages.dart`：聊天列表、用户/Agent 气泡、工具行渲染、`_scrollToBottom`。
- `markdown.dart`：MarkdownBody 样式表 `_markdownStyleSheet()` + 代码块渲染（`_PreTextBuilder`/`_CodeCopyButton` 顶层类）。
- `widgets.dart`：页面骨架（聊天主体/欢迎页/聊天区域/建议图标）。
- `models.dart`：`_ChatMessage`/`_ToolEvent`/`_QuestionPanel` 数据模型。
- `helpers.dart`：工具名称/参数/结果的显示格式化（纯展示辅助 extension）。

规则：
- 各功能块用 `extension on _HomeScreenState` 挂回状态类；新增功能进对应 part 文件，页面布局编排与业务逻辑分开维护，不要把新逻辑继续堆进主文件。
- 回调 tear-off（`addListener(_focusInput)`、`execute: _runCompact` 等）对 extension 成员直接可用（当前 SDK 支持 extension tear-off），勿为此引入新的全局单例或包装层。
- `models.dart` 的 toJson/fromJson 与会话落盘格式强耦合，改字段必须兼容旧会话文件。

## 聊天 '/' 命令

输入框输入 `/` 弹出命令提示（HomeScreen 输入框上方），分三层，新增命令不碰 UI：

- `lib/services/chat_command.dart`：`ChatCommand`（name/description/execute/behavior）+ `CommandPaletteController`（命令注册表、query 前缀过滤、键盘选中项，纯逻辑 ChangeNotifier）。`ChatCommandBehavior`：`immediate`（确认即执行，默认）/ `prepareInput`（确认后只把 `/命令名 ` 写回输入框，不执行动作；宿主按 behavior 分派 `_prepareInputCommand`，勿在 UI 硬编码判断具体命令名）。
- `lib/widgets/command_palette.dart`：纯展示列表，只读 controller 状态，确认回调交回宿主。
- `lib/screens/home_screen/commands.dart` `_buildCommands()`：命令注册表。**新增命令 = 在这里加一条 `ChatCommand`，execute 只调用处理方法，不内联业务逻辑**；处理方法放在 `command_actions.dart` 或按领域拆分的动作文件中，并自行 mounted 保护。
- 交互：↑/↓ 选择、Enter/Tab 确认（清空输入并执行）、Esc 收起、点击行确认；`/` 开头的输入不作为普通消息发送，命令面板支持名称前缀和分隔词首字母缩写匹配（如 `/cs` 匹配 `/clear-session`），发送时仍按命令精确匹配执行。
- 内置命令：`/help`、`/session`（历史会话弹窗，见下）、`/clear`（置空 `_conversation` 开新会话，旧会话文件保留）、`/compact`（AgentService.compact 压缩上下文，走 `_runCompact`）、`/rollback`（FileUndoService 还原最近一次文件改动）、`/retry`（删除末位回复并经 `_sendText` 重发，`_sendText` 是输入发送共用的核心流程；带附件时重发会恢复附件）、`/copy`（复制当前会话 JSON）、`/copy-txt`（复制当前会话文本）、`/image-analyze`（prepareInput，见"图片附件"节）、`/apps`、`/settings`（走 menuChannel）。本地结果消息统一走 `_addLocalMessage`。

## 图片附件与 /image-analyze

- 粘贴链路：`windows/runner/clipboard_image_channel.cpp`（`orbby_clipboard_image` 通道 `readImage`：CF_HDROP→图片文件路径；CF_DIBV5/CF_DIB/CF_BITMAP→WIC 编码 PNG 临时文件；每个 engine 注册一次，见 `RegisterClipboardImageChannel`）→ `lib/services/clipboard_image_service.dart`（mime 白名单 png/jpeg/webp/gif、单张 ≤10MB、缩略图/尺寸解码）→ `lib/services/chat_attachment_controller.dart`（sha256 去重、上限 4 张、超限提示、发送编码、持久化）→ `lib/widgets/chat_attachment_preview.dart`（缩略图三态+删除+点看大图 `chat_attachment_viewer.dart`）。
- 输入框接管 Ctrl+V（优先图片、无图回退手动文本插入）与 Alt+V（仅图片）；**请求进行中禁止追加附件**（transientError 提示）。`/clear`、`/new`、切换会话统一 `_attachmentCtrl.clear()`。
- **发送编码跑在 isolate**（controller 的 `_encodeForPayload`）：Base64 ≤6MB 原样透传（GIF 动画保留）；超限先缩到长边 4096 转 PNG，仍超限转 JPEG 92。编码结果缓存在 `ChatAttachment.sendPayload`（内存态，重载会话后由 `ensurePayload` 补算）。
- **Base64 绝不入会话 JSON**：附件文件随发送持久化到 `~/.orbby/attachments/{conversationId}/`（`persistAll`），消息落盘只存引用元数据（`_ChatMessage.attachments` 的 `attachments` 键）；发给 LLM 的 history 历史轮只有 `[图片: 文件名]` 引用（`_historyContent`），仅当前轮经 `chat.start` 的 `attachments` 发完整 Base64；取消/失败附件保留在消息上，`/retry` 恢复。
- `/image-analyze`（prepareInput）：确认后输入框留 `/image-analyze `，用户粘贴图片+补说明再回车；发送时 `_matchPrepareCommand` 剥前缀（不传给模型），说明为空用默认文案，无附件提示先粘贴且不调 AI。`_sendWithAttachments` 是带附件发送统一入口（视觉检查→编码→转移→`_sendText`）。
- **不做本地视觉能力判断**（名单式判断必然误杀迭代太快的新模型）：带附件直接发送，模型不支持时由 API 报错兜底，错误信息原样展示。`settings.platform` 随 `llm` payload 传给 Node 用于选 provider 格式。
- Node 侧：`agent-runtime/src/llm/content-adapter.ts` 定义统一 `LlmContent`（string 或 text/image 块，图片在前文字在后）+ `sanitizeAttachments`（Node 侧兜底校验数量/mime/大小）；`client.ts` 按 `platform` 分支 OpenAI-compatible（image_url）/ Anthropic（image block，system 提顶级、tool 结果合并 tool_result、input_json_delta 流式解析）；历史轮 `toPlainText` 只回放文本。

## Agent 提问卡片（输入框上方，非模态）

- `lib/models/agent_question.dart`：AgentQuestion/Option 模型，fromJson 容错（type 缺省按 options 是否为空推断，解析失败降级为 text 问题）。
- `lib/widgets/agent_question_panel.dart` 三件套：`AgentQuestionPanelController`（纯逻辑 ChangeNotifier：扁平导航游标、选择状态、answers 组装）+ `AgentQuestionPanel`（纯展示，配色抄 CommandPalette；单问题单选点击选项行即提交，多选/text 走底部按钮）+ `QuestionRecordCard`（已回答留痕卡，只读）。与 CommandPalette 同构的 controller+展示模式，新增问题类型扩展 controller 与 `_buildQuestion` 分支，勿在 home_screen 内联。
- home_screen 接入：`_questionCtrl`/`_questionId` 挂起状态（卡片插在 `_buildInputArea` 的 CommandPalette 之后，null 时不占位）；`_handleKeyEvent` 在命令面板分支**之后**接管 ↑↓/Enter/Esc（**输入框非空时不接管**，防拦截用户排队发送；Esc 始终跳过）；`chatStream` 流结束（完成/取消/断连）与 `/new`、`/clear` 统一走 `_dismissQuestionCard()` 收起卡片。
- 留痕：`_QuestionPanel`（home_screen/models.dart）随会话落盘（消息 map 的 `questionPanels` 键），重载经 `_decodeToolEvents` 还原，渲染在 ask_user_question 工具行下方；旧会话 JSON 无此键自然兼容。

## 聊天会话持久化与文件回滚

- **会话持久化**：HomeScreen 持有 `ChatConversation? _conversation`，经 `ChatStorageService` 落盘到 `~/.orbby/claude_task/task/`。落盘点：用户消息加入后、回复/压缩完成后、命令本地消息后。首轮发送时才创建会话（id 为毫秒时间戳，标题取首条用户消息）；切换会话（`_showSessionPicker` → `SessionPickerDialog`）前自动保存当前会话，agent 上下文由下次发送的 history 重建。**保存经 `_saveChain` 串行执行且链内吞错**（防快照交错、防一环失败毒化后续保存）；**`local` 消息（命令结果）不落盘也不进 history**——落盘会丢标志、重载后污染上下文。
- **文件改动回滚**：`lib/services/file_undo_service.dart`（`FileUndoService`）备份到 `~/.orbby/undo/`（manifest.json + 字节级 .bin 备份，上限 50 条）。写类工具挂钩：`edit_file`/`create_file`(overwrite) 写前 `recordEdit`，`create_file` 新建 `recordCreate`，`delete_file` 文件分支 `recordDelete`；**目录删除不备份，rollback 覆盖不到**。仅在 menu 窗口 engine 内使用（静态缓存安全，同 engine 工具与命令共享）。

## 组件通信（AppEvents）

跨窗口/组件的状态变更通知统一用 `AppEvents`（`lib/services/app_events.dart`），事件名集中定义在该类，禁止魔法字符串：

```
// 发出：本窗口立即生效，并自动扩散到所有窗口
AppEvents.emit(AppEvents.panelAppsChanged);

// 组件监听（参照 lib/widgets/app_square_panel.dart）
AppEvents.addListener(AppEvents.panelAppsChanged, _loadApps);
```

initState 注册、dispose 必须 removeListener；`_load` 中先 `if (!mounted) return` 再 `setState`。窗口控制类指令（place、switch_tab、open_app_center 等）不走总线，仍用定向 channel。
