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
// - markdown.dart    Markdown 样式表与代码块渲染
// - widgets.dart     页面骨架、欢迎页、聊天区域
// - models.dart      _ChatMessage/_ToolEvent/_QuestionPanel 数据模型
// - helpers.dart     工具名称/参数/结果的显示格式化
part 'commands.dart';
part 'command_actions.dart';
part 'input.dart';
part 'conversation.dart';
part 'agent.dart';
part 'messages.dart';
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
  final _messages = <_ChatMessage>[];
  String? _hoveredAction;
  String? _selectedAction;
  bool _isSending = false;
  final _queuedTexts = <String>[];
  Timer? _toolBlinkTimer;
  bool _toolBlinkOn = true;

  // 输入历史：按上/下键浏览已发送的消息，向下越过最新记录时恢复草稿。
  final _inputHistory = <String>[];
  int _historyIndex = -1;
  String _historyDraft = '';

  /// 当前会话（持久化）；null = 新对话尚未落盘，首轮发送时创建
  ChatConversation? _conversation;
  Future<void> _saveChain = Future<void>.value();

  /// '/' 命令面板：命令注册表见 commands.dart 的 [_HomeScreenCommands._buildCommands]
  late final _palette = CommandPaletteController(commands: _buildCommands());

  /// Agent 提问卡片（输入框上方）：null = 无挂起提问
  AgentQuestionPanelController? _questionCtrl;
  /// 当前提问的 questionId（与 [_questionCtrl] 同生命周期）
  String? _questionId;

  /// 输入框附件（粘贴的图片）：添加/删除/清空/发送编码统一走 controller
  final _attachmentCtrl = ChatAttachmentController();

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
    // 每次打开新的菜单窗口都使用新的 Agent 上下文，避免复用 runtime 中的 default session。
    AgentService.recreate();
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
    _questionCtrl?.dispose();
    _attachmentCtrl.dispose();
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
      home: Scaffold(
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
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 25),
                child: _buildChatBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
