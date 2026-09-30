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
import '../../services/menu_theme_service.dart';
import '../../services/chat_attachment_controller.dart';
import '../../services/clipboard_image_service.dart';
import '../../services/personality_service.dart';
import '../../services/chat_skill.dart';
import '../../services/skill_service.dart';
import '../../theme/chat_theme.dart';
import '../../config/settings.dart';
import '../../config/platform.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/skill_palette.dart';
import '../../widgets/session_picker_dialog.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/message_status_dot.dart';
import '../../widgets/code_highlight_text.dart';
import '../../widgets/file_change_preview.dart';
import '../../widgets/agent_question_panel.dart';
import '../../widgets/chat_attachment_preview.dart';
import '../../widgets/chat_attachment_viewer.dart';
import '../../models/file_change_preview.dart';
import '../../models/agent_question.dart';
import '../../models/chat_attachment.dart';

// HomeScreen 按功能拆分的 part 文件（同库，可互访私有成员）：
// - commands.dart    '/' 命令注册表 + Agent 设置弹窗
// - skills.dart      '@' 技能目录加载 + 面板确认
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
part 'skills.dart';
part 'command_actions.dart';
part 'input.dart';
part 'conversation.dart';
part 'agent.dart';
part 'messages.dart';
part 'tool_steps.dart';
part 'tabs.dart';
part 'markdown.dart';
part 'widgets.dart';
part 'function_bar.dart';
part 'models.dart';
part 'helpers.dart';

// =========================================================================
// 页面视觉常量（库级顶层：extension 内可直接裸名引用）
// =========================================================================

/// 窗口面板与屏幕边缘的留白（圆角 + 阴影的呼吸区）。
/// 与 hub 侧 WindowCoordinator 的 _menuMargin 必须一致——窗口矩形由
/// hub 的 place 消息按此值定位，Flutter 面板在本窗口内再内缩同样宽度。
/// 取值即阴影可见上限：投影只在窗口内绘制，超出窗口边界的部分被系统裁掉。
const _windowMargin = 8.0;

/// 聊天统一字体：正文与 UI 文案。与组件层同源（[ChatTheme.fontFamily]），
/// 换字体只改 chat_theme.dart；part 文件继续裸名引用本常量。
const _fontFamily = ChatTheme.fontFamily;

/// 代码字体：IDEA 同款 JetBrains Mono（无中文字形，中文由系统字体兜底）
const _codeFont = ChatTheme.codeFont;

// ─── 正文排版：字号 × 行高倍数 ────────────────────────────────────────────
// 消息正文的样式与「前面的状态圆点」共用这组值：圆点按首行行高垂直居中，
// 不再用固定 top 魔数。改字号/行高只动这里，两处自动同步。

/// 用户消息正文字号 / 行高倍数
const _userFontSize = 15.0;
const _userLineHeightFactor = 1.7;

/// AI 正文（Markdown 段落、列表项）字号 / 行高倍数
const _bodyFontSize = 15.0;
const _bodyLineHeightFactor = 1.85;

/// 图片分析时用户未补充说明的默认提问文案
const _defaultImagePrompt = '请分析这些图片，并描述其中的重要内容';

/// 混合/纯文档附件时用户未补充说明的默认提问文案
const _defaultAttachmentPrompt = '请分析这些附件的内容';

/// MaterialApp 主题缓存（浅 / 深各一份，避免每次 build 重建触发全树刷新）。
/// 字体与聊天正文同源（[_fontFamily]）——Material 自带组件（Tooltip、SnackBar、
/// 默认 Dialog 文字等）也走这一份，避免与手写文字混排两种字形。
final _materialThemes = {
  false: ThemeData(
    brightness: Brightness.light,
    fontFamily: _fontFamily,
  ),
  true: ThemeData(
    brightness: Brightness.dark,
    fontFamily: _fontFamily,
  ),
};

/// 聊天列表区主题（浅 / 深各一份）：选中高亮色随主题
final _listThemes = {
  for (final dark in [false, true])
    dark: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: dark
            ? ChatThemeData.dark.selectionColor
            : ChatThemeData.light.selectionColor,
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(0),
      ),
    ),
};

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

  // ─── 主题 ────────────────────────────────────────────────────────────────

  /// 深色主题开关（默认深色延续旧版观感）；持久化经 MenuThemeService。
  /// 所有 part 文件经 [_themeData] 取 token；弹窗（navigator 层 context
  /// 在 ChatThemeScope 之外）也直接读字段，不走 ChatTheme.of。
  bool _themeDark = true;
  bool _showSessionTabs = true;

  ChatThemeData get _themeData =>
      _themeDark ? ChatThemeData.dark : ChatThemeData.light;

  /// 顶栏右侧主题切换按钮：切换 + 落盘
  Future<void> _toggleTheme() async {
    setState(() => _themeDark = !_themeDark);
    await MenuThemeService.save(_themeDark);
  }

  // ─── 聊天状态 ────────────────────────────────────────────────────────────

  final _scrollController = ScrollController(keepScrollOffset: false);
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  String _modelLabel = '加载模型中…';
  String _workspaceLabel = '工作区';
  Timer? _toolBlinkTimer;
  Timer? _agentSettingsSaveTimer;
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

  /// '@' 技能面板：技能来自 ~/.orbby/skills/（见 skills.dart 的
  /// [_HomeScreenSkills._loadSkills]），启动时异步扫描注册
  late final _skillPalette = SkillPaletteController();

  /// Node 侧 skills.changed 推送（技能目录文件变化）的订阅，
  /// 见 [_HomeScreenSkills._subscribeSkillChanges]
  StreamSubscription<Map<String, dynamic>>? _skillsChangedSub;

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
    _loadWorkspaceLabel();
    _loadSkills();
    _subscribeSkillChanges();
    HomeScreen.menuChannel.invokeMethod('ready');
    // 恢复持久化的主题偏好（引擎就绪后一次性刷新）
    MenuThemeService.load().then((dark) {
      if (mounted && dark != _themeDark) setState(() => _themeDark = dark);
    });
    SettingsService.load().then((settings) {
      if (!mounted) return;
      final model = settings.model.trim().isEmpty
          ? PlatformConfig.defaultChatModel(settings.platform)
          : settings.model.trim();
      setState(() {
        _modelLabel = model;
        _showSessionTabs = settings.showSessionTabs;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final size = await windowManager.getSize();
      final display = await screenRetriever.getPrimaryDisplay();
      final position = display.visiblePosition ?? Offset.zero;
      final screenSize = display.visibleSize ?? display.size;
      // 悬浮窗几何：窗口矩形（= 面板 + 四周 _windowMargin 阴影区）贴屏幕右上边缘，
      // 面板边距由本窗口的 Padding 绘制。hub 的 _menuBounds 按同一几何定位，
      // 此处仅作窗口自身的最终校正（两处公式必须一致）
      await windowManager.setPosition(
        Offset(
          position.dx + screenSize.width - size.width,
          position.dy,
        ),
      );
    });
    // 每次窗口被显示时，输入框自动获得焦点
    menuWindowShown.addListener(_focusInput);
    // 输入内容驱动命令面板的过滤
    _inputController.addListener(_onInputChanged);
    _scrollController.addListener(_onChatScroll);
  }

  /// 输入内容驱动命令/技能面板过滤；'/' 与 '@' 按最后出现的触发字符
  /// 互斥路由（两个面板不会同时可见），未路由到的一方强制隐藏
  void _onInputChanged() {
    final text = _inputController.text;
    if (text.lastIndexOf('@') > text.lastIndexOf('/')) {
      _palette.hide();
      _skillPalette.updateQuery(text);
    } else {
      _skillPalette.hide();
      _palette.updateQuery(text);
    }
  }

  void _focusInput() {
    if (!_isSending) _inputFocus.requestFocus();
  }

  @override
  void dispose() {
    _toolBlinkTimer?.cancel();
    _agentSettingsSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    menuWindowShown.removeListener(_focusInput);
    _inputController.removeListener(_onInputChanged);
    _palette.dispose();
    _skillPalette.dispose();
    _skillsChangedSub?.cancel();
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
    final theme = _themeData;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _materialThemes[theme.isDark],
      navigatorKey: _navigatorKey,
      // 窗口级按键兜底（_handleWindowKeyEvent）：焦点不在输入框时也能 Ctrl+C/Esc 终止。
      // 只监听不抢焦点（canRequestFocus: false），不参与 tab 遍历。
      home: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleWindowKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // 窗口本体视觉：透明窗口内四周留 [_windowMargin] 给阴影，
          // 面板 = surface 底 + 12px 圆角 + 1px 描边 + 柔和投影（参考稿形态）
          body: ChatThemeScope(
            data: theme,
            child: Padding(
              padding: const EdgeInsets.all(_windowMargin),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.line),
                  boxShadow: theme.windowShadows,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildChatBody(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
