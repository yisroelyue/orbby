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

- Agent 的 ReAct 工具循环运行在 `agent-runtime/` Node.js 子进程中，通过 localhost WebSocket 与 Flutter 通信。每轮文本经 `agent.token` 流式发出，工具循环最多 30 个 step；Flutter 的 `AgentService.chatStream` 继续转换为 `AgentTokenEvent`/`AgentRoundEvent`，Dart 侧不再运行 Agent 核心。
- **流式契约：processMessage 正常完成时返回值 = 最后一轮已流出的 content，chatStream 对已流出过 token 的会话只关流不补发返回值（防整段重复）。因此 processMessage 内所有"额外兜底文案"（超轮次/上下文超硬限/空回复）必须自行经 `onToken` 发出再 return，否则 UI 会在已有文字后静默收尾，看起来像卡死。**
- HomeScreen 收到 `AgentRoundEvent` 时在气泡内插 `\n\n---\n\n` 分隔轮次；该拼接文本随会话落盘、也作为 history 发回 LLM。**新增事件类型（如工具调用进度）时扩展 AgentStreamEvent 子类 + 各消费方 switch**，不要回退成裸字符串流（多轮文字会粘成一坨）。
- `lib/agent/llm_client.dart` 的 HTTP 层收敛为公共骨架，**新增 LLM provider 复用骨架，勿再复制重试/超时逻辑**：`_withRetry`（统一重试+退避，`retryable` 回调供流式路径拦截"已流出内容"的重试，防 UI 文本重复）+ `_post`（连接/首字节超时、client 生命周期）+ `_readBody`/`_sseLines`（响应体读取超时：SSE 空闲 60s 每行重置、非流式整体 120s）。四个 `_call*` 方法只留协议差异（headers、body 组装 `_compatibleBody`/`_anthropicBody`、解析 `_parse*`），超时常量集中在类顶部。
- **用户提问（ask_user_question / 目录权限确认）**：问题结构化 `AgentQuestion`（question/header/type(choice|text)/options/multiSelect，契约定义在 `agent-runtime/src/protocol.ts`，Flutter 侧模型在 `lib/models/agent_question.dart`，两端字段一致）；`user.answer` payload 为 `answers: string[][]`（按问题索引对应，空数组=跳过）。挂起的提问 promise 存在 **per-connection** 的 answers Map（value 含 requestId/resolve/reject）：**chat.cancel 与 socket close 必须 reject 挂起问题**，否则工具 worker 卡死并经 runExclusive 锁死整个会话。目录权限确认（workspace-permission）复用同一通道，答案按 `answers[0][0] === '允许'` 精确匹配（勿回退成字符串包含匹配）。

## 聊天 '/' 命令

输入框输入 `/` 弹出命令提示（HomeScreen 输入框上方），分三层，新增命令不碰 UI：

- `lib/services/chat_command.dart`：`ChatCommand`（name/description/execute/behavior）+ `CommandPaletteController`（命令注册表、query 前缀过滤、键盘选中项，纯逻辑 ChangeNotifier）。`ChatCommandBehavior`：`immediate`（确认即执行，默认）/ `prepareInput`（确认后只把 `/命令名 ` 写回输入框，不执行动作；宿主按 behavior 分派 `_prepareInputCommand`，勿在 UI 硬编码判断具体命令名）。
- `lib/widgets/command_palette.dart`：纯展示列表，只读 controller 状态，确认回调交回宿主。
- `lib/screens/home_screen.dart` `_buildCommands()`：命令注册表。**新增命令 = 在这里加一条 `ChatCommand`**；execute 里操作 HomeScreen 状态需自行 mounted 保护。
- 交互：↑/↓ 选择、Enter/Tab 确认（清空输入并执行）、Esc 收起、点击行确认；`/` 开头的输入不作为普通消息发送，按命令精确匹配执行。
- 内置命令：`/help`、`/session`（历史会话弹窗，见下）、`/clear`（置空 `_conversation` 开新会话，旧会话文件保留）、`/compact`（AgentService.compact 压缩上下文，走 `_runCompact`）、`/rollback`（FileUndoService 还原最近一次文件改动）、`/retry`（删除末位回复并经 `_sendText` 重发，`_sendText` 是输入发送共用的核心流程；带附件时重发会恢复附件）、`/copy`（复制当前会话 JSON）、`/copy-txt`（复制当前会话文本）、`/image-analyze`（prepareInput，见"图片附件"节）、`/apps`、`/settings`（走 menuChannel）。本地结果消息统一走 `_addLocalMessage`。

## 附件（图片/文本/PDF）与 /image-analyze

- 附件三类 mime：图片（png/jpeg/webp/gif，原样 Base64 直传）、文本类（**统一记 `text/plain`**，真实类型看扩展名，覆盖 txt/md/csv/json/代码/配置等）、`application/pdf`。**设计原则：在 Node 边界把一切归一化为 text/image 两种内容块**（各 provider 最大公约数），client.ts 的协议分支不感知具体文件类型；新格式（docx/xlsx…）= `attachment-extractor.ts` 加一个提取器条目，其余层不动。
- 粘贴链路：`windows/runner/clipboard_image_channel.cpp`（`orbby_clipboard_image` 通道 `readImage`：CF_HDROP→支持扩展名的文件路径（`IsSupportedFileExtension`）；**有文件但类型不支持且无可粘贴内容时返回 `kind=file-unsupported`+路径**；CF_DIBV5/CF_DIB/CF_BITMAP→WIC 编码 PNG 临时文件；每个 engine 注册一次，注释纯 ASCII）→ `lib/services/clipboard_image_service.dart`（`readFromClipboard` 返回 `ClipboardImageReadResult{read, unsupportedFileName}`；mime 白名单、分类型大小上限：图片 10MB/文本 5MB/PDF 20MB、图片缩略图/尺寸解码）→ `lib/services/chat_attachment_controller.dart`（sha256 去重、上限 4 个、非图片不解码直接就绪、发送编码、持久化保留原扩展名）→ `lib/widgets/chat_attachment_preview.dart`（图片缩略图三态；非图片图标+文件名+大小）。
- 输入框接管 Ctrl+V（优先附件、无图回退手动文本插入，**不支持文件且无文本可粘时提示「暂不支持」**）与 Alt+V（仅图片，不支持文件直接提示）；**请求进行中禁止追加附件**。`/clear`、`/new`、切换会话统一 `_attachmentCtrl.clear()`。
- **发送编码跑在 isolate**（controller 的 `_encodeForPayload`）：非图片原样 Base64 透传不转码；图片 Base64 ≤6MB 原样透传（GIF 动画保留），超限先缩到长边 4096 转 PNG，仍超限转 JPEG 92。编码结果缓存在 `ChatAttachment.sendPayload`（内存态，重载会话后由 `ensurePayload` 补算）。
- **Base64 绝不入会话 JSON**：附件文件随发送持久化到 `~/.orbby/attachments/{conversationId}/`（`persistAll`），消息落盘只存引用元数据；history 历史轮只有 `[图片: 文件名]`/`[附件: 文件名]` 引用（`_historyContent`），仅当前轮经 `chat.start` 的 `attachments` 发完整 Base64；取消/失败附件保留在消息上，`/retry` 恢复。
- 非图片附件点击**调系统默认程序打开**（`openAttachment`，explorer.exe），不做应用内文档渲染；`/image-analyze` 仍是图片专用命令。
- **不做本地视觉能力判断**（名单式判断必然误杀迭代太快的新模型）：带附件直接发送，模型不支持时由 API 报错兜底，错误信息原样展示。`settings.platform` 随 `llm` payload 传给 Node 用于选 provider 格式。
- Node 侧：`agent-runtime/src/llm/content-adapter.ts` 定义统一 `LlmContent` + `attachmentKind(mime)` 分类 + `sanitizeAttachments`（分类型 Base64 上限：图片 14M/文本 7M/PDF 28M）；**`attachment-extractor.ts` 在 `runtime.chat` 组装内容前把文本/PDF 提取为文本**写入 `WsAttachment.extractedText/extractedInfo`（unpdf 按页提取带页码、BOM 嗅探 UTF-8/16、单文件 5 万字符 + 总量 12 万字符预算、超限显式标注"内容不完整"、失败以文本呈现不静默丢）；`toUserContent` 图片块+文档文本块在前、正文（含附件说明，防模型去本地搜"源文件"）在后；`client.ts` 按 `platform` 分支 OpenAI-compatible（image_url）/ Anthropic（image block，system 提顶级、tool 结果合并 tool_result、input_json_delta 流式解析）；历史轮 `toPlainText` 只回放文本。Anthropic 原生 PDF document block 留作后续 platform 增强。

## Agent 提问卡片（输入框上方，非模态）

- `lib/models/agent_question.dart`：AgentQuestion/Option 模型，fromJson 容错（type 缺省按 options 是否为空推断，解析失败降级为 text 问题）。
- `lib/widgets/agent_question_panel.dart` 三件套：`AgentQuestionPanelController`（纯逻辑 ChangeNotifier：扁平导航游标、选择状态、answers 组装）+ `AgentQuestionPanel`（纯展示，配色抄 CommandPalette；单问题单选点击选项行即提交，多选/text 走底部按钮）+ `QuestionRecordCard`（已回答留痕卡，只读）。与 CommandPalette 同构的 controller+展示模式，新增问题类型扩展 controller 与 `_buildQuestion` 分支，勿在 home_screen 内联。
- home_screen 接入：`_questionCtrl`/`_questionId` 挂起状态（卡片插在 `_buildInputArea` 的 CommandPalette 之后，null 时不占位）；`_handleKeyEvent` 在命令面板分支**之后**接管 ↑↓/Enter/Esc（**输入框非空时不接管**，防拦截用户排队发送；Esc 始终跳过）；`chatStream` 流结束（完成/取消/断连）与 `/new`、`/clear` 统一走 `_dismissQuestionCard()` 收起卡片。
- 留痕：`_QuestionPanel`（home_screen_models.dart）挂在**对应 `ask_user_question` 的 `_ToolEvent.questionPanels` 上**（渲染在工具行下面，与 FileChangesPanel 同级），随 toolEvents 落盘/还原；定位规则 = 最后一条含 running ask_user_question 工具行的消息；中断（Ctrl+C/断连）时不留痕。

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
