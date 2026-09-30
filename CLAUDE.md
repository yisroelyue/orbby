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
- 子窗口：`menu`（聊天 HomeScreen）、`settings`、`app_bar`、`content`、`app_center`、`about`。menu/settings/app_bar/content 启动时预创建（hiddenAtLaunch；各窗口创建函数排进自己的 operation 链防与 toggle 双创建竞态），常驻窗口用 hide/show 切换；app_center/about 每次新建。**预创建顺序固定 menu → app_bar → settings → content 且各间隔 1.5s**：多 engine 连续启动存在时序竞态——紧跟上一窗口 ready 立即创建下一个，偶发新 engine 的 Dart main() 永不执行（native 构造正常、isolate 不跑，ready 超时、place 报 CHANNEL_UNREGISTERED）；原 settings→app_bar 紧邻顺序曾 4/4 必挂。
- 窗口通信（本地 fork 的 `packages/desktop_multi_window`）两条路：
  - `WindowMethodChannel(..., ChannelMode.unidirectional)`：全局仅 hub 注册 handler，任何 engine 都能 invoke → **子→hub**（ready、hidden、open_settings 等）。
  - `window.invokeMethod(...)` 定向调用子窗口的 `setWindowMethodHandler` → **hub→子**（place、app_event 等）。
- **ready 握手**：子窗口 engine 就绪后发 `'ready'`，hub 等 Completer（5s 超时兜底）再 place/show；不等的话首次 place 会丢。

## 主界面（menu 窗口）主题与窗口形态

- **两套主题 token 集中在 `lib/theme/chat_theme.dart`**（`ChatThemeData`，浅/深各一个 `static const`）：三层底色（`surface` 窗口底 / `raised` 浮起卡片 / `sunken` 沉底代码块）+ 卡片顶栏灰（`barBg`，中性灰，与暖调的 `sunken` 分开——顶栏压不住黄调）+ 四级文字（`ink` 最强 / `body` 正文 / `ink2` 元信息 / `ink3` 最弱）+ 琥珀主色（`accent`/`accentDeep`/`accentSoft`）+ 语义色（`ok`/`danger`/`info` 及各 `*Soft`）+ 三级阴影（`windowShadows`/`cardShadows`/`popShadows`）。**主界面新增颜色一律在这里加 token，禁止在组件里写死色值**（例外：发给系统/无关主题的地方，如琥珀发送钮上的墨色图标、大图查看器黑遮罩上的白字）。
- **字体同源收在 `chat_theme.dart`**：正文/UI = `ChatTheme.fontFamily`（`Microsoft YaHei`，系统字体），代码块与工具 diff/路径 = `ChatTheme.codeFont`（`JetBrains Mono`，内嵌，无中文字形、中文由系统兜底）。**组件禁止硬编码字体名**；HomeScreen 的 part 文件继续裸名引用库级常量 `_fontFamily`/`_codeFont`（值即上面两个）。字体与明暗无关，故不做成 `ChatThemeData` 字段。注意 Sarasa 与 JetBrains 在 pubspec 里只声明了 Regular(400)/Bold(700) 两档，`FontWeight.w500`~`w600` 会实际落到 Bold——要真正的中间粗细须再内嵌一份并在 pubspec 声明对应 `weight`。
- **正文排版常量集中在 `home_screen.dart` 顶部**：`_userFontSize`/`_userLineHeightFactor`（用户消息气泡）与 `_bodyFontSize`/`_bodyLineHeightFactor`（Markdown 段落、列表项），样式与圆点共用同一组值。消息行首的状态圆点（`MessageStatusDot.lineHeight`）按首行行高**算**出垂直居中，**不得退回固定 top 魔数**——魔数是按某一档字号凑出来的，字号一改（如整体 +1px）圆点立刻与正文错位。
- **代码块行号（`markdown.dart` 的 `_PreTextBuilder`）**：行号样式必须由 `codeStyle.copyWith(color: …)` 派生——字号/行高倍数与代码完全一致，**不要各自写值**（`height` 是随字号缩放的倍数，两处一旦不同行号就会逐行漂移）。行号列固定在左侧、不随代码横向滚动，末尾换行不计行号。
- **flutter_markdown 是本地 fork（`packages/flutter_markdown`，`dependency_overrides` 指向，同 desktop_multi_window 模式；上游已停更，0.7.7+1 即最终版）**：改动 = 新增两个 `MarkdownStyleSheet` 字段：`tableHeadDecoration`（表头行背景；上游把表头行装饰硬编码 null，`tableCellsDecoration` 实为表体斑马纹）与 `tableDecoration`（整表外层容器：底色/描边/圆角裁剪，`_buildTable` 里包 `ClipRRect`+`DecoratedBox`）。上游 `builders['table']` 返回值会被丢弃、`builders['th']` 会破坏单元格插入，表格定制别走这两条死路。另修了 `_addAnonymousBlockIfNeeded`：对没收集到 children 的悬空 `_InlineElement` 也 `_inlines.clear()`（上游只在 children 非空时清）——自定义 block builder（如项目侧 'pre' 全量接管）的 `visitText` 返回 null 时，上游会留下空悬空元素，踩 `build()` 末尾的 `assert(_inlines.isEmpty)` 崩溃、且后续文本会追加到带错误样式的悬空元素上。fork 内改动点搜 `Orbby fork`。项目侧表格样式集中在 `_markdownStyleSheet()`：整表 raised 底 + line 描边 + 10px 圆角卡、表头 barBg 灰带 + w400 左对齐（上游 fallback 默认居中，须显式传 `tableHeadAlign: left`）、无竖线、仅 `horizontalInside` hairline。
- **取用分三路（关键）**：
  1. HomeScreen 的 part 文件（`home_screen/*.dart`）直接读 State 字段 `_themeData`——part extension 拿不到 Scope（Scope 是 State 元素的后代）。
  2. `lib/widgets/` 下的展示组件走 `ChatTheme.of(context)`，由 `ChatThemeScope` 提供；Scope 只包在 `Scaffold.body` 内。
  3. **弹窗（`showDialog`）挂在 navigator 层，在 Scope 之外**，此时 `ChatTheme.of` 会静默回退深色。正确做法二选一：宿主 `builder` 里再包一层 `ChatThemeScope(data: _themeData, child: …)`（见 `_showSessionPicker`），或组件直接收宿主传入的 `ChatThemeData`（见 `_PreTextBuilder`、`_ToolStepsGroup`）。**不要在弹窗里裸用 `ChatTheme.of`**。
- 主题偏好持久化在 `lib/services/menu_theme_service.dart` → `~/.orbby/setting/menu_theme.json`，**刻意独立成小文件，不复用设置页的 `orbby_settings.json`**（menu 与 settings 是两个 engine，并发写同一文件会互相覆盖）。默认深色。切换入口 = tab 栏右端 `_buildThemeToggleButton`（同排还有「＋」新建会话）。
- **窗口形态：圆角 + 阴影 + 边距走纯 Flutter 实现，不用 native 区域裁剪**。`SetWindowRgn` 同时管渲染与命中测试——inset 会连阴影一起裁掉，全窗 region 又挡不住边缘点击，两者不可兼得。现方案：窗口 `transparent` + 无系统阴影，Flutter 侧在窗口内留边距画面板（`Padding` → `DecoratedBox`(surface / 圆角 12 / `line` 描边 / `windowShadows`) → `ClipRRect` → `_buildChatBody`）。
- **窗口几何两端必须一致**：hub 的 `WindowCoordinator._menuMargin` 与 menu 窗口 `home_screen.dart` 的库级常量 `_windowMargin` **改一个必须改另一个**。hub 的 `_menuBounds()` 按它定位窗口矩形（窗口宽 = 屏宽 × `_menuWidthFactor` + 两侧 margin，所以面板宽度仍是屏宽 1/3），Flutter 侧再在窗口内内缩同值画面板；窗口整体贴屏幕右上边缘。
- **`_windowMargin` 同时是阴影可见上限**：投影只能画在窗口内，超出窗口边界的部分被系统裁掉。故 `windowShadows` 的 blur/spread 已按该值收敛（≠ 参考稿里那组给设计稿背景看的大参数）；想要更强的投影必须先加大 margin。
- **聊天主列的 children 位置必须稳定（易踩，已踩过一次）**：`_buildChatBody` 的 Column 固定为 `[tab 栏, Expanded(空态品牌区 / 聊天列表), 输入区]`，**输入区永远在末位、不放进空态分支内部**；`_buildInputArea` 里的提问卡片也用三目 + `SizedBox.shrink()` 占位，不用 `if (...)` 条件展开。原因：Column 的 children 无 key、按索引 diff，且末尾对齐用的是**旧列表长度**——某一层一旦多/少一个 child，它后面的兄弟全被判为不匹配、整棵销毁重建（输入框文字、焦点、附件、命令面板状态全丢），还会连带崩 `InheritedElement._dependents.isEmpty` 断言（输入框的 `TextFieldTapRegion` 被选择工具栏的 overlay 元素跨子树依赖，TextField 子树 deactivate 时 dependent 仍在）。新增会显隐的兄弟节点，一律三目占位保索引。
- **已知边界**：边距区（窗口内的透明部分）仍接收点击，只是不穿透到桌面。menu 是失焦即隐藏的悬浮工具窗，这个代价可接受。

## Agent 流式协议

- Agent 的 ReAct 工具循环运行在 `agent-runtime/` Node.js 子进程中，通过 localhost WebSocket 与 Flutter 通信。每轮文本经 `agent.token` 流式发出，工具循环最多 30 个 step；Flutter 的 `AgentService.chatStream` 继续转换为 `AgentTokenEvent`/`AgentRoundEvent`，Dart 侧不再运行 Agent 核心。
- **工作区（workspacePath，per-session）**：所有工具的相对路径基准与命令默认 cwd，**按 sessionId 隔离（多会话并发的关键，严禁回退成 runtime 级全局单值——A 会话跑工具循环期间 B 会话 `/cd` 会让 A 的后续工具跑到错误目录）**。解析优先级：会话内存值（`AgentSession.workspacePath`，惰性初始化）> 会话持久化值（`workspace.json` 的 `sessions[sessionId]`，同会话重开恢复）> 全局默认（顶层 `workspace`，= 最近一次 `/cd` 的目录）> `ORBBY_WORKSPACE` env > 桌面默认；会话条目上限 50 按 LRU 淘汰（`agent-runtime/src/services/workspace-storage.ts`）。`/cd` 经 `workspace.set` 消息切换（`AgentRuntime.setWorkspace(sessionId, path)`：按**该会话**当前工作区 resolve 相对路径、校验目录存在、更新内存 + `saveSessionWorkspace` 持久化并刷新全局默认），`workspace.get` 查询（两者都回 `workspace.status`，server 侧都带 sessionId）。**chat 轮内快照**：`runExclusive` 内开始处取一次 `sessionWorkspace(sessionId)`，该轮 system 提示与全部工具调用共用同一基准，轮中途（其他会话/本会话排队期间）的 `/cd` 只影响下一轮；`executeTools` 同样走 per-session。
- **流式契约：processMessage 正常完成时返回值 = 最后一轮已流出的 content，chatStream 对已流出过 token 的会话只关流不补发返回值（防整段重复）。因此 processMessage 内所有"额外兜底文案"（超轮次/上下文超硬限/空回复）必须自行经 `onToken` 发出再 return，否则 UI 会在已有文字后静默收尾，看起来像卡死。**工具循环 30 步耗尽同理：走 `onToken` 兜底文案 + `turn.end(reason:max_steps)` 后 return，勿 throw（异常会让 UI 以"请求失败"收尾，错误文本还会落盘污染 history）。
- **文件编辑工具匹配语义（`agent-runtime/src/tools/fs-tools.ts`）**：`read` 行号与内容用 **`\t` 分隔，严禁改回空格分隔**——空格分隔符会被模型并入行首缩进（缩进 +2），构造出的 edit oldString 必然精确匹配失败（会话 8964be45 实测 12 次 `not found` 皆此因，还连锁烧光 30 步）；`edit` 统一在归一化 LF 视图上匹配（read 展示已把 CRLF 归一化，模型只能写出 `\n` 的 oldString，原样字节匹配对 CRLF 文件的多行替换必然失败），写回时还原文件原换行风格；匹配失败时错误信息附带按首行去空白找到的实际行内容（真实缩进），供模型一次纠对，勿回退成裸 "not found"。
- HomeScreen 收到 `AgentRoundEvent` 时在气泡内插 `\n\n---\n\n` 分隔轮次；该拼接文本随会话落盘、也作为 history 发回 LLM。**新增事件类型（如工具调用进度）时扩展 AgentStreamEvent 子类 + 各消费方 switch**，不要回退成裸字符串流（多轮文字会粘成一坨）。
- **流式气泡定位必须持引用**：`_sendText` 的流式 AI 气泡用局部 `reply` 变量跟踪（切轮次/切泡时更新引用），严禁回退成 `_messages.last`——流式期间用户排队新任务会在末尾插入 `->next task:` 气泡，`_messages.last` 错位会把 AI 回复拼进排队消息。
- `lib/agent/llm_client.dart` 的 HTTP 层收敛为公共骨架，**新增 LLM provider 复用骨架，勿再复制重试/超时逻辑**：`_withRetry`（统一重试+退避，`retryable` 回调供流式路径拦截"已流出内容"的重试，防 UI 文本重复）+ `_post`（连接/首字节超时、client 生命周期）+ `_readBody`/`_sseLines`（响应体读取超时：SSE 空闲 60s 每行重置、非流式整体 120s）。四个 `_call*` 方法只留协议差异（headers、body 组装 `_compatibleBody`/`_anthropicBody`、解析 `_parse*`），超时常量集中在类顶部。
- **用户提问（ask_user_question / 目录权限确认）**：问题结构化 `AgentQuestion`（question/header/type(choice|text)/options/multiSelect，契约定义在 `agent-runtime/src/protocol.ts`，Flutter 侧模型在 `lib/models/agent_question.dart`，两端字段一致）；`user.answer` payload 为 `answers: string[][]`（按问题索引对应，空数组=跳过）。挂起的提问 promise 存在 **per-connection** 的 answers Map（value 含 requestId/resolve/reject）：**chat.cancel 与 socket close 必须 reject 挂起问题**，否则工具 worker 卡死并经 runExclusive 锁死整个会话。目录权限确认（workspace-permission）复用同一通道，答案按 `answers[0][0] === '允许'` 精确匹配（勿回退成字符串包含匹配）。
- **多会话并发模型（Node 侧已就绪）**：上下文与锁按 sessionId 隔离（`AgentRuntime.sessions` map + `AgentSession.runExclusive`，不同会话并行、同会话排队）；server 层 `active`/`answers` 按 WebSocket 连接隔离，requestId/questionId 全局唯一，多会话共用一条连接也互不干扰。`permissionMode` 是**全局**语义（设置页下发，`chat.start` 时快照传入，运行中切换不影响进行中的一轮）——多会话共用同一权限模式是有意设计。已知边界：`TerminalManager` 是全局共享终端池，`terminal_send/close` 不校验终端归属于哪个会话，多会话 UI 落地时如需隔离再做归属过滤。
- **多会话 tab UI（Flutter 侧）**：HomeScreen 顶部 tab 栏（`home_screen/tabs.dart`）切换/关闭会话（新建走 `/new` 命令，`_openNewSessionTab`；tab 数上限 `_maxSessionTabs`=4——tab 宽为栏宽 1/4 恰好占满一行，超限提示先关闭再新建）。每个 tab 一个 `ChatSessionView`（`home_screen/models.dart`：conversation/messages/queuedTexts/isSending/questionCtrl/questionId/inputDraft/attachmentCtrl/agentSessionId/scrollOffset+atBottom），`_HomeScreenState` 以 `_views` 列表 + `_activeIndex` 管理，`_current` 转发为旧字段名（`_messages`/`_conversation`/`_isSending` 等 getter/setter），渲染层与命令层零改动、只作用于前台。**三条硬纪律**：① 流式写入路径（`agent.dart` 的 `_sendText` 及其队列续发）必须在开头捕获 `final view = target ?? _current` 并全程直写 view 字段——流式期间用户可能切走 tab，经 `_current` 间接写会把内容串进前台会话；② `_scrollToBottom` 带 view 参数，仅当 view 是当前 tab 才滚动（共享 scrollController，后台会话流式增长不得拽动前台）；③ **滚动位置按会话保存**（scrollOffset/atBottom 瞬态字段）：切换/新建 tab 换源前 `_saveScrollState()` 存回、换源后 `_restoreScrollState()` 跳回（贴底恢复贴底、非贴底跳回离开位置，clamp 防内容变短越界），**严禁在切换后强制 `_scrollToBottom(force: true)`**——那会把用户正在看的历史位置拽丢；关后台 tab 不得拽动前台滚动；消息整体换源（`/session` 原地加载、`/clear`）后必须 `resetScrollState()`。`AgentService` 各方法带可选 `sessionId` 参数（per-session 的 chatStream/compact/status/resetConversation/workspace/answerQuestion；`_activeRequests` 按 sessionId 登记，`cancelCurrent({sessionId})` 各会话独立取消）。关闭 tab 时 cancel + `session.reset` 回收 Node 内存会话（防孤儿累积，`recreate()` 已删除）；后台会话挂起提问时卡片不可见，tab 上以红点提醒（运行中橙点闪烁）。`AgentWsClient.connect` 缓存连接中 Future——多会话并发首发的竞态会连出多条 socket。

## 聊天 '/' 命令

输入框输入 `/` 弹出命令提示（HomeScreen 输入框上方），分三层，新增命令不碰 UI：

- `lib/services/chat_command.dart`：`ChatCommand`（name/description/execute/behavior/executeWithArgument）+ `CommandPaletteController`（命令注册表、query 前缀过滤、键盘选中项，纯逻辑 ChangeNotifier）。`ChatCommandBehavior`：`immediate`（确认即执行，默认）/ `prepareInput`（确认后只把 `/命令名 ` 写回输入框，不执行动作；宿主按 behavior 分派 `_prepareInputCommand`，勿在 UI 硬编码判断具体命令名）。**prepareInput 命令带参形态 `/命令名 参数`**：`_sendMessage` 经 `_matchPrepareCommand` 剥前缀后调命令的 `executeWithArgument`；直接发送纯命令名（trim 后无参数）以空参数执行（如 `/cd` 查看当前工作区）——准备态写回输入框只发生在命令面板确认路径，勿在 `_sendMessage` 对纯命令名走准备态（`_sendMessage` 的 trim 会吃掉尾随空格，会死循环回准备态）。
- `lib/widgets/command_palette.dart`：纯展示列表，只读 controller 状态，确认回调交回宿主。
- `lib/screens/home_screen.dart` `_buildCommands()`：命令注册表。**新增命令 = 在这里加一条 `ChatCommand`**；execute 里操作 HomeScreen 状态需自行 mounted 保护。
- 交互：↑/↓ 选择、Enter/Tab 确认（清空输入并执行）、Esc 收起、点击行确认；`/` 开头的输入不作为普通消息发送，按命令精确匹配执行。
- 内置命令：`/help`、`/new`（另开新的会话 tab，走 `_openNewSessionTab`；旧会话原地保留可切回）、`/session`（历史会话弹窗，见下）、`/clear`（清空当前 tab 上下文并删除该会话文件）、`/clear-session`（删除全部历史会话文件，关闭所有多余 tab 只留一个空 tab；不走 `_closeSessionTab` 防落盘把删除的文件写回）、`/compact`（AgentService.compact 压缩上下文，走 `_runCompact`）、`/rollback`（FileUndoService 还原最近一次文件改动）、`/retry`（删除末位回复并经 `_sendText` 重发，`_sendText` 是输入发送共用的核心流程；带附件时重发会恢复附件）、`/copy`（复制当前会话 JSON）、`/copy-txt`（复制当前会话文本）、`/cd`（prepareInput，切换 Agent 工作区：`/cd 路径` 相对路径按当前工作区解析、空参数查看当前，Node 侧校验并持久化）、`/apps`、`/settings`（走 menuChannel）、`/reload-skill`（重扫技能目录并清 Node 技能缓存，见「聊天 '@' 技能」）。本地结果消息统一走 `_addLocalMessage`。

## 聊天 '@' 技能

输入框输入 `@` 弹出技能提示（HomeScreen 输入框上方），与 '/' 命令面板同构的三层，新增技能不碰代码（数据在磁盘）：

- `lib/services/chat_skill.dart`：`ChatSkill`（name/description）+ `SkillPaletteController`（纯逻辑 ChangeNotifier，过滤/键盘导航与命令面板同款）。**触发语义与命令不同**：技能嵌在正文中引用，只有 `@` 片段位于**文本末尾**（`@` 之后无空白）面板才可见——空格续写正文即自然收起，Enter 发送不被劫持；确认是把末尾 `@ 片段`替换为 `@技能名 `（保留前后正文，不清空输入框，见 `home_screen/skills.dart` 的 `_confirmSkill`）。
- `lib/services/skill_service.dart`：扫 `~/.orbby/skills/`，**两种技能形态可混用**：目录式（推荐，子目录内 `SKILL.md` = frontmatter `name`/`description` + 正文，同目录其余文件是脚本/模板等技能资源；name 缺省用目录名）与散装单 md（name 缺省用文件名 stem）；frontmatter 极简解析，name 含空白的跳过（`@` 引用片段以空白截止）；**同名技能目录式优先**；目录不存在时创建并 seed 目录式 demo 技能（SKILL.md + usage.txt）。
- `lib/widgets/skill_palette.dart`：纯展示列表，视觉与 CommandPalette 同源。
- **'/' 与 '@' 面板互斥路由**：`home_screen.dart` 的 `_onInputChanged` 按最后出现的触发字符（`lastIndexOf` 比较）只路由给一个 controller，另一个 `hide()`（两面板永不同时 visible；键盘接管分支在 `input.dart` 命令面板之后并列）。
- **面板共用关键词匹配**抽在 `lib/services/palette_filter.dart`（`paletteMatchRank`：前缀 > 分隔词缩写 > 顺序匹配），命令/技能两个 controller 复用，勿在其中一处另写匹配规则。
- **发送链路（Node 侧展开）**：`agent-runtime/src/services/skill-service.ts` 与 Flutter 共用 `~/.orbby/skills/`，扫同两种形态（同样目录式优先），读 md 正文；`runtime.ts` 的 `chat()` 在两处调 `expandSkillRefs`——当前轮 user 消息、以及会话重开时 history 回放的 user 轮（Flutter 传回的 history 是原始文本，不展开则重开后引用轮丢技能正文）。**展开形态 = 原句保留 + 末尾附加技能指令块**（同名去重、未注册的 `@xxx` 原样保留、`@` 后到空白或常见中英文标点截止）；目录式技能的注入块附带**资源目录绝对路径 + 一层文件清单**（>20 项截断），LLM 经命令工具以绝对路径执行脚本、read 工具读资源——技能作者不硬编码路径。UI 气泡与会话落盘仍是原始文本，仅发给 LLM 的上下文带正文。
- **技能名与目录名支持中文**（两端扫描、面板过滤、注入均兼容）；中文引用与正文粘连（"用@磁盘扫描整理一下"无空格分隔）由 `resolveSkillRef` 的**最长前缀兜底**解决——精确匹配失败时取"是引用串前缀"的技能中最长者，手打与面板选中（自动补尾随空格）两条路径都能展开。技能附带 `.ps1` 脚本须**纯 ASCII**：无 BOM 的 UTF-8 会被 PowerShell 5.1 按 GBK 读，中文注释/输出即乱码（同 runner C++ 的坑）。
- **技能目录只读白名单**：`workspace-permission.ts` 的 `ensure` 对 `~/.orbby/skills` 下的 read 操作直接放行（LLM 会主动读注入的资源路径，逐次弹确认体验差）；write/execute 仍走原授权模型。
- 技能列表两端都在内存缓存；**`/reload-skill` 命令热加载**：Flutter 重扫（`SkillPaletteController.replaceAll` 整表替换）+ `skills.reload` 消息清 Node 缓存（`clearSkillCache`，下次 `expandSkillRefs` 重扫），加/改技能文件无需重启应用。改了 agent-runtime 的 src 记得 `npx tsc` 编译 dist（Flutter 从 `dist/main.js` 启动 Node）。
- **技能目录变更自动热加载（监听，无需命令）**：Node 侧 `skill-service.ts` 的 `startSkillsWatch` 用 `fs.watch(recursive)` 监听 `~/.orbby/skills`（目录不存在先建、watcher 异常 5s 后重建），变更防抖 1s 后 `clearSkillCache` 并由 server 向所有连接广播 `skills.changed`；连接建立时也补推一次（断连期间错过的变更兜底）。Flutter 侧 `AgentService.serverEvents`（`AgentWsClient.events` 直通）暴露推送流，HomeScreen 的 `_subscribeSkillChanges`（skills.dart）过滤 `skills.changed` 后静默 `_loadSkills()` 重扫面板——LLM 创建技能/用户手改文件后立即可 `@` 引用，`/reload-skill` 降级为兜底。订阅 serverEvents 必须 `onError` 吞断连错误（broadcast 流的错误发给所有订阅者）。**新增服务端主动推送类型照此模式**：server 广播 + AgentService.serverEvents 暴露 + 消费方按 type 过滤，不走请求-响应。
- **`@创建技能` 元技能**（`~/.orbby/skills/创建技能/`）：教 LLM 按用户需求创建新技能（在技能根目录建子目录 + SKILL.md + 可选脚本，引用 `<技能资源目录>` 父目录推导根目录），写完靠上面的目录监听自动生效。写入技能目录**仍走授权弹窗**（read 才白名单）——技能正文是指令注入载体，放行 write 等于技能可无感改写技能库，这条线刻意不开。

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
- `lib/widgets/agent_question_panel.dart` 三件套：`AgentQuestionPanelController`（纯逻辑 ChangeNotifier：扁平导航游标、选择状态、answers 组装）+ `AgentQuestionPanel`（纯展示，配色抄 CommandPalette；单问题单选点击选项行即提交，多选/text 走底部按钮）+ `QuestionRecordCard`（已回答留痕卡，只读；**一问题一卡**——顶部 `sunken` 条放问题全文 + header 琥珀标签，下方内容区放「用户回复：…」，与代码块同构的两段式卡片，多问题纵向叠卡）。与 CommandPalette 同构的 controller+展示模式，新增问题类型扩展 controller 与 `_buildQuestion` 分支，勿在 home_screen 内联。
- home_screen 接入：`_questionCtrl`/`_questionId` 挂起状态（卡片插在 `_buildInputArea` 的 CommandPalette 之后，null 时不占位）；`_handleKeyEvent` 在命令面板分支**之后**接管 ↑↓/Enter/Esc（**输入框非空时不接管**，防拦截用户排队发送；Esc 始终跳过）；`chatStream` 流结束（完成/取消/断连）与 `/new`、`/clear` 统一走 `_dismissQuestionCard()` 收起卡片。
- 键盘终止兜底：`input.dart` 的 `_handleWindowKeyEvent` 挂在 build 最外层 `Focus`（`canRequestFocus: false, skipTraversal: true`，只监听不抢焦点）上：焦点不在输入框时 Ctrl+C 终止任务、Esc 取消提问/终止任务。按键沿焦点链从 primaryFocus 向上冒泡，输入框 handler 与 SelectionArea 复制快捷键都在更内层、先 handled 先生效，本层只兜底，新增全局按键优先考虑挂这里。
- 留痕：`_QuestionPanel`（home_screen_models.dart）挂在**对应 `ask_user_question` 的 `_ToolEvent.questionPanels` 上**（渲染在工具行下面，与 FileChangesPanel 同级），随 toolEvents 落盘/还原；定位规则 = 最后一条含 running ask_user_question 工具行的消息；中断（Ctrl+C/断连）时不留痕。

## 工具步骤折叠组（聊天 UI）

- 一条消息气泡内 ≥2 个工具调用渲染为折叠组（`lib/screens/home_screen/tool_steps.dart` 的 `_ToolStepsGroup`）：默认**全部折叠只显示概览头** = 运行状态前缀（任一运行中"正在执行"/全部完成"已执行"）+ 项数 + **去重操作名列表**（同名只显示一次、全部列出，超长 ellipsis）+ 失败数红字，圆点闪烁表示运行中，点击头部展开/收起（头部包 `SelectionContainer.disabled`，防 SelectionArea 吞点击）；展开的行整体缩进（left 16）。单工具仍原样直出。
- 行渲染统一走 `messages.dart` 的 `_buildToolRow`（直出与折叠详情共用，勿复制行 UI）；折叠状态在 `_ChatMessage.toolsExpanded`（**瞬态不落盘**，重载会话默认折叠）。工具名中文映射 `toolDisplayName` 是 helpers.dart 的**库级顶层函数**（折叠组与状态类共用，勿移回 extension）。折叠组的 `theme` 由宿主显式传入（不依赖 context，见主题小节第 3 点）。
- 不变式：气泡内工具行始终连续位于正文之前（agent.dart 切泡逻辑保证），一条消息至多一个折叠组；分组按消息内 toolEvents 整体折叠，不做条级部分折叠。

## 聊天会话持久化与文件回滚

会话存储目录为 `~/.orbby/task/`；新会话 ID 使用随机 UUID，不再使用时间戳或 `task_` 前缀。会话目录内的会话数据固定保存为 `conversation.json`，交互请求/响应日志为 `request.log`，事件日志为 `events.log`。不兼容旧的 `<id>.json` 文件。

- **会话持久化**：每个 tab 的 `ChatSessionView` 持有各自的 `ChatConversation? conversation`，经 `ChatStorageService` 落盘到 `~/.orbby/claude_task/task/`。落盘点：用户消息加入后、回复/压缩完成后、命令本地消息后。首轮发送时才创建会话（id 为随机 UUID，标题取首条用户消息）；`/session` 切换（`_showSessionPicker` → `SessionPickerDialog`）把历史会话加载进**当前 tab**（加载前自动保存，agent 上下文由下次发送的 history 重建）。**保存经 `_saveChain` 串行执行且链内吞错**（全部 tab 共用一条链，防快照交错、防一环失败毒化后续保存）；**`_saveConversation([view])` 在流式收尾/关 tab 时必须显式传 view**（目标会话可能已不在前台）；**`local` 消息（命令结果）不落盘也不进 history**——落盘会丢标志、重载后污染上下文。
- **文件改动回滚**：`lib/services/file_undo_service.dart`（`FileUndoService`）备份到 `~/.orbby/undo/`（manifest.json + 字节级 .bin 备份，上限 50 条）。写类工具挂钩：`edit_file`/`create_file`(overwrite) 写前 `recordEdit`，`create_file` 新建 `recordCreate`，`delete_file` 文件分支 `recordDelete`；**目录删除不备份，rollback 覆盖不到**。仅在 menu 窗口 engine 内使用（静态缓存安全，同 engine 工具与命令共享）。

## 笔记浮窗（note 窗口：笔记 / 密码本双视图）

500×800 固定窗口内以头部工具栏图标按钮切换「笔记 / 密码本」两个视图（IndexedStack 保状态），不新增窗口/页面。视觉 token 与共用组件集中在 `lib/screens/note/note_theme.dart`（颜色/卡片装饰/HoverBuilder/IconAction/TextAction/PrimaryButton/DashedPlaceholder/LogoMark），勿在视图里内联样式。

- 拆分：`note_screen.dart` = 外壳（头部 logo+标题副标题+切换按钮+拖动柄、底部主按钮、闲置计时；经 GlobalKey 调子视图 public 方法）；`note/notes_view.dart` = 笔记列表+编辑器（状态自管，统计经 onStats 回调外壳）；`note/passwords_view.dart` = 密码本（PIN 状态机+列表+详情+表单，onStatus 回调）。新增视图态扩展对应子视图，勿把逻辑搬回外壳。
- 头部整个区域可拖动（onPanStart startDragging）+ onTap 收起笔记编辑器；子按钮手势优先级更高不冲突。
- **PasswordVault**（`lib/services/password_service.dart`，**仅 note engine 内使用**）：6 位数字主密码 PBKDF2-SHA256（12 万轮+随机盐，isolate 派生防卡 UI）→ AES-256-CBC 整体加密落盘 `~/.orbby/orbby_vault.json`；明文前缀魔数校验 PIN；count 明文存文件头供锁定态副标题。解锁后明文仅驻内存（静态 `_entries`），`lock()` 即清除。条目字段 title/username/password/kind（key/card/server/doc 四类图标 = assets/svg/ 同名 svg）。损坏库文件改名 `.corrupt` 备份后按未设置处理。
- 安全策略（外壳协调）：**切回笔记视图立即锁定**（`lockNow()` 清内存明文+复位全部编辑/揭示状态）、解锁态闲置 5 分钟自动锁定（指针+键盘事件重置计时，仅密码本视图+已解锁时武装）、连续输错 3 次冷却 30 秒（倒计时期间禁提交）。锁定/设置态无底部按钮。
- 密码条目交互：折叠行两行（名称+账号）+掩码（点数=密码长度上限 12）+行内眼睛临时明文（等宽 JetBrains Mono）；点击展开详情卡（名称/账号/密码三行，展开默认明文）+复制/编辑/删除（删除走确认对话框，danger 色）；同时仅一条展开。
- 已知边界：note 窗口被 hub 隐藏时若密码本已解锁，明文仍驻留内存（hide 不通知 note engine），下次显示仍保持解锁；如需更严需 hub 隐藏时定向发锁定指令。

## 组件通信（AppEvents）

跨窗口/组件的状态变更通知统一用 `AppEvents`（`lib/services/app_events.dart`），事件名集中定义在该类，禁止魔法字符串：

```
// 发出：本窗口立即生效，并自动扩散到所有窗口
AppEvents.emit(AppEvents.panelAppsChanged);

// 组件监听（参照 lib/widgets/app_square_panel.dart）
AppEvents.addListener(AppEvents.panelAppsChanged, _loadApps);
```

initState 注册、dispose 必须 removeListener；`_load` 中先 `if (!mounted) return` 再 `setState`。窗口控制类指令（place、switch_tab、open_app_center 等）不走总线，仍用定向 channel。
