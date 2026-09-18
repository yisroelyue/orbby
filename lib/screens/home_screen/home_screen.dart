import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../../services/agent_service.dart';
import '../../services/chat_command.dart';
import '../../services/chat_storage_service.dart';
import '../../services/chat_log_service.dart';
import '../../services/file_undo_service.dart';
import '../../services/menu_window_signals.dart';
import '../../services/chat_attachment_controller.dart';
import '../../services/clipboard_image_service.dart';
import '../../services/personality_service.dart';
import '../../config/settings.dart';
import '../../config/platform.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/frosted_panel.dart';
import '../../widgets/session_picker_dialog.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/message_status_dot.dart';
import '../../widgets/file_change_preview.dart';
import '../../widgets/agent_question_panel.dart';
import '../../widgets/chat_attachment_preview.dart';
import '../../widgets/chat_attachment_viewer.dart';
import '../../models/file_change_preview.dart';
import '../../models/agent_question.dart';
import '../../models/chat_attachment.dart';

// HomeScreen 按功能拆分的 part 文件（同库，可互访私有成员）：
// - commands.dart    '/' 命令注册表 + Agent 设置弹窗
// - input.dart       输入区 UI、输入历史、键盘交互
// - conversation.dart 会话创建/保存/切换/复制/解码
// - agent.dart       消息发送、Agent 流处理、提问卡片应答
// - messages.dart    聊天列表与消息气泡渲染
// - tool_steps.dart  工具步骤折叠组（多工具调用默认折叠，概览头 + 可展开详情）
// - tabs.dart        顶部会话 tab 栏（多会话切换/新建/关闭）
// - markdown.dart    Markdown 样式表与代码块渲染
// - widgets.dart     页面骨架、欢迎页、聊天区域
// - models.dart      ChatSessionView/_ChatMessage/_ToolEvent/_QuestionPanel 数据模型
// - helpers.dart     工具名称/参数/结果的显示格式化
part 'commands.dart';
part 'command_actions.dart';
part 'input.dart';
part 'conversation.dart';
part 'agent.dart';
part 'messages.dart';
part 'tool_steps.dart';
part 'tabs.dart';
part 'markdown.dart';
part 'widgets.dart';
part 'models.dart';
part 'helpers.dart';

// =========================================================================
// 页面视觉常量（库级顶层：extension 内可直接裸名引用）
// =========================================================================

/// 缓存避免每次 build 重建 ThemeData 触发全树刷新
final _theme = ThemeData(
  fontFamily: 'Microsoft YaHei',
  scaffoldBackgroundColor: Colors.grey,
);

/// 面板深灰黑背景（比聊天区 0xFF1E1E1E 略亮，形成分层）
const _panelBg = Color(0xFF252526);

const _scaffoldBg = Color(0xFF191A1C);

/// 会话 tab 栏（Windows Terminal 风格）：栏底 _panelBg 上只有激活 tab 一个色块，
/// 色块 = _scaffoldBg（与内容区同色无缝，视觉上是"从页面凸出的一块"）；
/// 非激活 tab 透明融入栏底，hover 用 [_tabHoverBg] 轻微提亮
const _tabHoverBg = Color(0x0DFFFFFF);
const _inputBg = Color(0xFF2A2A2A);
const _inputText = Color(0xB3FFFFFF);
const _inputHint = Color(0x4DFFFFFF);
const _chipActiveBg = Color(0x26FFFFFF);
const _chipActiveText = Color(0xB3FFFFFF);
const _userBubble = Color(0xFF3A3A3A);

/// 正文灰白——纯白在深底上太刺眼
const _bubbleText = Color(0xFFC0C0C0);
const _statusText = Colors.white;
const _dividerColor = Color(0xFF3A3A3A);

/// Markdown 元素配色：代码与链接区别于正文白色
const _codeText = Color(0xFF56A8F5);

/// 代码块文字
const _codeBlockText = Color(0xFFC0C0C0);
const _codeBlockBg = Color(0xFF101215);
const _linkText = Color(0xFF64B5F6);

/// 聊天统一字体：更纱黑体——西文为内嵌等宽，中文严格两倍宽，终端格子感
const _fontFamily = 'Sarasa Mono SC';

/// 代码字体：IDEA 同款 JetBrains Mono（无中文字形，中文回退更纱黑体）
const _codeFont = 'JetBrains Mono';

/// 图片分析时用户未补充说明的默认提问文案
const _defaultImagePrompt = '请分析这些图片，并描述其中的重要内容';

/// 混合/纯文档附件时用户未补充说明的默认提问文案
const _defaultAttachmentPrompt = '请分析这些附件的内容';

/// 列表区主题固定，缓存避免每次 build 重建 ThemeData
final _listTheme = ThemeData(
  brightness: Brightness.dark,
  textSelectionTheme: const TextSelectionThemeData(
    // 选中文字的背景高亮色
    selectionColor: Color(0xFF4A4A4A),
  ),
  scrollbarTheme: const ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(0),
  ),
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const menuChannel = WindowMethodChannel(
    'orbby_menu_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 页面状态与整体编排：可变状态字段、生命周期、布局骨架都在本文件；
/// 各功能块（命令/输入/会话/Agent 流/消息渲染等）拆在同目录 part 文件，
/// 通过 extension on _HomeScreenState 挂回状态类。
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// 菜单窗口是否曾获得焦点（用于失焦自动隐藏）
  bool _wasFocused = false;

  // ─── 聊天状态 ────────────────────────────────────────────────────────────

  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  String? _hoveredAction;
  String? _selectedAction;
  Timer? _toolBlinkTimer;
  bool _toolBlinkOn = true;
  bool _showScrollToBottom = false;

  // ─── 多会话 tab 状态 ─────────────────────────────────────────────────────
  // 所有"会话内容"状态（消息/草稿/流式/提问/附件）都挂在 ChatSessionView 上；
  // 下方 getter/setter 把"当前 tab"转发为旧字段名，渲染层与命令层零改动。
  // 流式写入路径（agent.dart 的 _sendText）禁止走这些转发——必须持 view 引用。

  /// 打开的会话 tab（有序）；至少恒有一个
  final _views = <ChatSessionView>[];
  int _activeIndex = 0;

  ChatSessionView get _current => _views[_activeIndex];
  List<_ChatMessage> get _messages => _current.messages;
  ChatConversation? get _conversation => _current.conversation;
  set _conversation(ChatConversation? value) => _current.conversation = value;
  bool get _isSending => _current.isSending;
  set _isSending(bool value) => _current.isSending = value;
  List<String> get _queuedTexts => _current.queuedTexts;
  AgentQuestionPanelController? get _questionCtrl => _current.questionCtrl;
  set _questionCtrl(AgentQuestionPanelController? value) =>
      _current.questionCtrl = value;
  String? get _questionId => _current.questionId;
  set _questionId(String? value) => _current.questionId = value;
  ChatAttachmentController get _attachmentCtrl => _current.attachmentCtrl;

  // 输入历史：按上/下键浏览已发送的消息，向下越过最新记录时恢复草稿。
  // 全窗口共享（浏览的是"这个输入框"发过的内容，不分会话）
  final _inputHistory = <String>[];
  int _historyIndex = -1;
  String _historyDraft = '';

  Future<void> _saveChain = Future<void>.value();

  /// '/' 命令面板：命令注册表见 commands.dart 的 [_HomeScreenCommands._buildCommands]
  late final _palette = CommandPaletteController(commands: _buildCommands());

  /// MaterialApp 内部的 Navigator context：
  /// HomeScreen 自身在 MaterialApp 之上，它的 context 弹窗找不到 MaterialLocalizations
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _toolBlinkTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted) setState(() => _toolBlinkOn = !_toolBlinkOn);
    });
    WidgetsBinding.instance.addObserver(this);
    // 每次打开新的菜单窗口都使用新的 Agent 上下文（新 agentSessionId），
    // 避免复用 runtime 中的 default session；首个会话 tab 同步建立。
    _views.add(ChatSessionView(agentSessionId: AgentService.newSessionId()));
    HomeScreen.menuChannel.invokeMethod('ready');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      final display = await screenRetriever.getPrimaryDisplay();
      final screenSize = display.visibleSize ?? display.size;
      final adjustedSize = Size(size.width + 1, size.height);
      await windowManager.setSize(adjustedSize);
      await windowManager.setPosition(
        Offset(screenSize.width - adjustedSize.width, 0),
      );
    });
    // 每次窗口被显示时，输入框自动获得焦点
    menuWindowShown.addListener(_focusInput);
    // 输入内容驱动命令面板的过滤
    _inputController.addListener(_onInputChanged);
    _scrollController.addListener(_onChatScroll);
  }

  void _onInputChanged() => _palette.updateQuery(_inputController.text);

  void _focusInput() {
    if (!_isSending) _inputFocus.requestFocus();
  }

  @override
  void dispose() {
    _toolBlinkTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    menuWindowShown.removeListener(_focusInput);
    _inputController.removeListener(_onInputChanged);
    _palette.dispose();
    // 所有 tab 的挂起提问卡片与附件 controller 一并释放
    for (final view in _views) {
      view.questionCtrl?.dispose();
      view.attachmentCtrl.dispose();
    }
    _scrollController.removeListener(_onChatScroll);
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wasFocused = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 菜单已获得过焦点再失焦时，自动隐藏
        if (_wasFocused) {
          _wasFocused = false;
          HomeScreen.menuChannel.invokeMethod('close_menu');
        }
        break;
      default:
        break;
    }
  }

  // =========================================================================
  // Build（页面骨架；聊天主体/欢迎页见 widgets.dart）
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme,
      navigatorKey: _navigatorKey,
      // 窗口级按键兜底（_handleWindowKeyEvent）：焦点不在输入框时也能 Ctrl+C/Esc 终止。
      // 只监听不抢焦点（canRequestFocus: false），不参与 tab 遍历。
      home: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleWindowKeyEvent,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(-10, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: FrostedPanel(
              color: _panelBg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildChatBody()),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
