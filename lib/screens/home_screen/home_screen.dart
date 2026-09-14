import 'dart:async';
import 'dart:convert';
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
import '../../config/settings.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/frosted_panel.dart';
import '../../widgets/session_picker_dialog.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/message_status_dot.dart';
import '../../widgets/file_change_preview.dart';
import '../../widgets/agent_question_panel.dart';
import '../../models/file_change_preview.dart';
import '../../models/agent_question.dart';

part 'home_screen_helpers.dart';
part 'home_screen_models.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const menuChannel = WindowMethodChannel(
    'orbby_menu_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // =========================================================================
  // 窗口壳
  // =========================================================================

  /// 缓存避免每次 build 重建 ThemeData 触发全树刷新
  static final _theme = ThemeData(
    fontFamily: 'Microsoft YaHei',
    scaffoldBackgroundColor: Colors.grey,
  );

  /// 面板深灰黑背景（比聊天区 0xFF1E1E1E 略亮，形成分层）
  static const _panelBg = Color(0xFF252526);

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

  /// '/' 命令面板：命令注册表见 [_buildCommands]
  late final _palette = CommandPaletteController(commands: _buildCommands());

  /// Agent 提问卡片（输入框上方）：null = 无挂起提问
  AgentQuestionPanelController? _questionCtrl;
  /// 当前提问的 questionId（与 [_questionCtrl] 同生命周期）
  String? _questionId;

  /// MaterialApp 内部的 Navigator context：
  /// HomeScreen 自身在 MaterialApp 之上，它的 context 弹窗找不到 MaterialLocalizations
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// 列表区主题固定，缓存避免每次 build 重建 ThemeData
  static final _listTheme = ThemeData(
    brightness: Brightness.dark,
    textSelectionTheme: const TextSelectionThemeData(
      // 选中文字的背景高亮色
      selectionColor: Color(0xFF4A4A4A),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(0),
    ),
  );

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

  // ─── 颜色 ──────────────────────────────────────────────────────────────

  static const _scaffoldBg = Color(0xFF191A1C);
  static const _inputBg = Color(0xFF2A2A2A);
  static const _inputText = Color(0xB3FFFFFF);
  static const _inputHint = Color(0x4DFFFFFF);
  static const _chipActiveBg = Color(0x26FFFFFF);
  static const _chipActiveText = Color(0xB3FFFFFF);
  static const _userBubble = Color(0xFF3A3A3A);

  /// 正文灰白——纯白在深底上太刺眼
  static const _bubbleText = Color(0xFFC0C0C0);
  static const _statusText = Colors.white;
  static const _dividerColor = Color(0xFF3A3A3A);

  /// Markdown 元素配色：代码与链接区别于正文白色
  static const _codeText = Color(0xFF56A8F5);

  /// 代码块文字
  static const _codeBlockText = Color(0xFFC0C0C0);
  static const _codeBlockBg = Color(0xFF101215);
  static const _linkText = Color(0xFF64B5F6);

  /// 聊天统一字体：更纱黑体——西文为内嵌等宽，中文严格两倍宽，终端格子感
  static const _fontFamily = 'Sarasa Mono SC';

  /// 代码字体：IDEA 同款 JetBrains Mono（无中文字形，中文回退更纱黑体）
  static const _codeFont = 'JetBrains Mono';

  // =========================================================================
  // Build
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

  // ─── 聊天主体 ───────────────────────────────────────────────────────────

  Widget _buildChatBody() {
    final isEmpty = _messages.isEmpty && !_isSending;
    return Container(
      decoration: const BoxDecoration(
        color: _scaffoldBg,
        // 底部贴面板底边，圆角交给外层 ClipRRect 裁
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: isEmpty ? _buildWelcomeScreen() : _buildChatArea(),
    );
  }

  // ─── 欢迎页 ─────────────────────────────────────────────────────────────

  Widget _buildWelcomeScreen() {
    return Column(
      children: [
        const Spacer(),
        // 临时隐藏：三个提示按钮
        // _buildSuggestionIcons(),
        // const SizedBox(height: 8),
        _buildInputArea(),
      ],
    );
  }

  /// 三个提示入口：只有图标，水平排列，点击直接发送对应提问
  Widget _buildSuggestionIcons() {
    const items = [
      ('assets/png/agentHint/1.png', '你好，请介绍你的功能。'),
      ('assets/png/agentHint/2.svg', '给我一些创意灵感和建议。'),
      ('assets/png/agentHint/3.svg', '请帮我写一段代码。'),
    ];
    return Row(
      children: [
        for (final (iconPath, prompt) in items) ...[
          _buildSuggestionIconButton(iconPath, prompt),
          const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildSuggestionIconButton(String iconPath, String prompt) {
    final isHovered = _hoveredAction == prompt;
    final isSvg = iconPath.endsWith('.svg');
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredAction = prompt),
      onExit: (_) => setState(() => _hoveredAction = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _inputController.text = prompt;
          _sendMessage();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isHovered
                ? _chipActiveBg.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: isSvg
              ? SvgPicture.asset(iconPath, width: 16, height: 16)
              : Image.asset(iconPath, width: 16, height: 16),
        ),
      ),
    );
  }

  // ─── 聊天区域 ──────────────────────────────────────────────────────────

  Widget _buildChatArea() {
    const showTyping = false;
    return Column(
      children: [
        Expanded(child: _buildChatList()),
        if (showTyping) ...[
          const SizedBox(height: 8),
          const TypingIndicator(),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        // 临时隐藏：三个提示按钮
        // _buildSuggestionIcons(),
        // const SizedBox(height: 8),
        _buildInputArea(),
      ],
    );
  }

  // ─── 输入框 ─────────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // '/' 命令提示列表，展开在输入框正上方
        CommandPalette(
          controller: _palette,
          onConfirm: _confirmCommand,
        ),
        // Agent 提问卡片：无挂起提问时为零高度空盒，不占位
        if (_questionCtrl != null)
          AgentQuestionPanel(
            controller: _questionCtrl!,
            onSubmit: _submitAgentAnswer,
            onSkip: _skipAgentQuestion,
          ),
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            controller: _inputController,
            focusNode: _inputFocus,
            minLines: 1,
            maxLines: 10,
            enabled: true,
            cursorColor: Colors.white,
            style: TextStyle(
                color: _inputText,
                fontSize: 14,
                fontFamily: _fontFamily),
            decoration: InputDecoration(
              hintText: _isSending ? '' : 'Type something or use /help to list commands',
              hintStyle: TextStyle(
                  color: _inputHint,
                  fontSize: 14,
                  fontFamily: _fontFamily),
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              filled: true,
              fillColor: _inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide.none,
              ),
              suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton(
                        icon: SvgPicture.asset('assets/svg/发送.svg',
                            width: 22, height: 22),
                        onPressed: _sendMessage,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── '/' 命令 ───────────────────────────────────────────────────────────

  /// 命令注册表：新增命令在这里加一条 ChatCommand 即可
  List<ChatCommand> _buildCommands() {
    return [
      ChatCommand(
        name: 'help',
        description: '查看所有命令',
        execute: () {
          final buf = StringBuffer('可用命令：');
          for (final c in _palette.commands) {
            buf.write('\n- `/${c.name}` — ${c.description}');
          }
          _addLocalMessage(buf.toString());
        },
      ),
      ChatCommand(
        name: 'session',
        description: '查看并切换历史会话',
        execute: () => _showSessionPicker(),
      ),
      ChatCommand(
        name: 'new',
        description: '开启新对话，可通过 /session 命令找回历史会话',
        execute: () {
          if (!mounted) return;
          AgentService.recreate();
          // 旧会话文件保留，下次发送创建新会话
          setState(() {
            _conversation = null;
            _messages.clear();
            _dismissQuestionCard();
          });
        },
      ),
      ChatCommand(
        name: 'clear',
        description: '清空当前上下文，但继续使用当前会话',
        execute: () {
          if (!mounted) return;
          AgentService.resetConversation();
          setState(() {
            _messages.clear();
            _queuedTexts.clear();
            _dismissQuestionCard();
          });
        },
      ),
      ChatCommand(
        name: 'compact',
        description: '压缩对话上下文',
        execute: () => _runCompact(),
      ),
      ChatCommand(
        name: 'rollback',
        description: '回滚上一次文件改动',
        execute: () => _addLocalMessage(FileUndoService.undoLast()),
      ),
      ChatCommand(
        name: 'retry',
        description: '重新生成最后一条回复',
        execute: () {
          if (!mounted || _isSending) return;
          final lastUser = _messages.lastIndexWhere((m) => m.isUser);
          if (lastUser < 0) return;
          final text = _messages[lastUser].text;
          // 丢掉最后一条用户消息及其后的所有回复，重新发送
          setState(() => _messages.removeRange(lastUser, _messages.length));
          _sendText(text);
        },
      ),
      ChatCommand(
        name: 'copy',
        description: '复制当前会话的完整 JSON',
        execute: _copyConversationJson,
      ),
      ChatCommand(
        name: 'copy-txt',
        description: '复制当前会话的文本内容',
        execute: _copyConversationText,
      ),
      ChatCommand(
        name: 'apps',
        description: '打开应用中心',
        execute: () => HomeScreen.menuChannel.invokeMethod('open_app_center'),
      ),
      ChatCommand(
        name: 'sys_setting',
        description: '打开设置窗口',
        execute: () => HomeScreen.menuChannel.invokeMethod('open_settings'),
      ),
      ChatCommand(
        name: 'setting',
        description: '打开 Agent 设置',
        execute: _showAgentSettings,
      ),
    ];
  }

  /// /compact：压缩上下文，摘要作为一条本地回复显示
  Future<void> _runCompact() async {
    if (!mounted || _isSending) return;
    if (_messages.isEmpty) {
      _addLocalMessage('当前没有对话可压缩。');
      return;
    }
    setState(() {
      _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
      _isSending = true;
    });
    _scrollToBottom(force: true);
    try {
      final summary = await AgentService.compact();
      if (!mounted) return;
      setState(() => _messages.last.text = summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.last.text = '压缩失败: $e');
    }
    if (mounted) {
      setState(() {
        _messages.last.streaming = false;
        _isSending = false;
      });
    }
    _saveConversation();
    _focusInput();
  }

  /// 确认（Enter/Tab/点击）命令：清空输入并执行。
  /// 键盘路径不传参，取当前选中项；点击路径传被点的命令
  void _confirmCommand([ChatCommand? cmd]) {
    cmd ??= _palette.confirm();
    if (cmd == null) return;
    _inputController.clear();
    cmd.execute();
  }

  // ─── 会话持久化 ─────────────────────────────────────────────────────────

  /// 当前对话落盘（~/.orbby/task）；空对话不创建文件。
  /// 首轮发送时创建会话，标题取第一条用户消息。
  /// 保存请求串行执行（_saveChain），避免两次快照交错落盘；
  /// 链内吞错——一环失败不能毒化后续所有保存。
  Future<void> _saveConversation() {
    _saveChain = _saveChain.then((_) async {
      try {
        var msgs = <Map<String, String>>[
          for (final m in _messages)
            // local 消息（命令结果）是瞬时提示，不落盘：
            // 否则重载会话后 local 标志丢失，会混进下次发送的 history
            if ((m.text.isNotEmpty || m.toolEvents.isNotEmpty) && !m.local)
              {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
                if (m.fileChanges.isNotEmpty) 'fileChanges': jsonEncode(m.fileChanges.map((e) => e.toJson()).toList()),
                if (m.toolEvents.isNotEmpty) 'toolEvents': jsonEncode(m.toolEvents.map((e) => e.toJson()).toList()),
              },
        ];
        if (msgs.isEmpty) return;
        _conversation ??= ChatConversation(
          id: ChatStorageService.newConversationId(),
          title: _messages
              .firstWhere((m) => m.isUser && !m.local,
                  orElse: () => _messages.first)
              .text,
        );
        final conv = _conversation!;
        if (conv.title.isEmpty) {
          conv.title = msgs.first['content'] ?? '未命名会话';
        }
        conv.messages
          ..clear()
          ..addAll(msgs);
        await ChatStorageService.save(conv);
      } catch (_) {
        // 落盘失败静默跳过，聊天主流程不受影响
      }
    });
    return _saveChain;
  }

  /// 插入一条本地 assistant 消息（命令结果等），并落盘
  void _addLocalMessage(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: false, local: true));
    });
    _scrollToBottom(force: true);
    _saveConversation();
  }

  /// /session：打开历史会话弹窗，选择后切换（切换前自动保存当前会话）
  Future<void> _copyConversationJson() async {
    if (!mounted) return;
    if (_conversation == null) {
      _addLocalMessage('当前还没有可复制的会话。');
      return;
    }
    await _saveConversation();
    if (!mounted) return;
    final json = const JsonEncoder.withIndent('  ').convert(_conversation!.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    _addLocalMessage('当前会话已复制到剪贴板。');
  }

  Future<void> _copyConversationText() async {
    if (!mounted) return;
    final messages = _messages.where((message) => !message.local && message.text.isNotEmpty).toList();
    if (messages.isEmpty) {
      _addLocalMessage('当前还没有可复制的会话。');
      return;
    }
    final text = messages.map((message) {
      final role = message.isUser ? '用户' : '助手';
      return '$role：\n${message.text}';
    }).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    _addLocalMessage('当前会话文本已复制到剪贴板。');
  }

  Future<void> _showSessionPicker() async {
    if (!mounted) return;
    if (_isSending) {
      _addLocalMessage('回复进行中，结束后再切换会话。');
      return;
    }
    await _saveConversation();
    final conversations = await ChatStorageService.loadAll();
    if (!mounted) return;
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final selected = await showDialog<ChatConversation>(
      context: navContext,
      barrierColor: Colors.black54,
      builder: (_) => SessionPickerDialog(conversations: conversations),
    );
    if (selected == null || !mounted) return;
    final conv = await ChatStorageService.load(selected.id) ?? selected;
    // agent 上下文由下次发送携带的 history 重建
    AgentService.resetConversation();
    setState(() {
      _conversation = conv;
      _messages
        ..clear()
        ..addAll([
          for (final m in conv.messages)
            _ChatMessage(
              text: m['content'] ?? '',
              isUser: m['role'] == 'user',
            )
              ..fileChanges.addAll(_decodeChanges(m['fileChanges']))
              ..toolEvents.addAll(_decodeToolEvents(m['toolEvents'])),
        ]);
    });
    _scrollToBottom(force: true);
  }

  List<FileChangePreview> _decodeChanges(String? raw) { if (raw == null || raw.isEmpty) return []; try { final list = jsonDecode(raw) as List; return list.whereType<Map>().map((e) => FileChangePreview.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) { return []; } }

  List<_ToolEvent> _decodeToolEvents(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) => _ToolEvent.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── 发送消息 ──────────────────────────────────────────────────────────

  Future<void> _showAgentSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    final prompt = TextEditingController(text: settings.agentSystemPrompt);
    final rules = TextEditingController(text: settings.agentUsageRules);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.all(20),
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Expanded(child: Text('Agent 设置', style: TextStyle(color: Color(0xFFEAEAEA), fontSize: 14, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close, size: 18, color: Colors.white54)),
              ]),
              const SizedBox(height: 18),
              TextField(controller: prompt, maxLines: 6, style: const TextStyle(color: Colors.white70), decoration: const InputDecoration(labelText: '自定义系统提示词', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), filled: true, fillColor: Color(0xFF292929))),
              const SizedBox(height: 14),
              TextField(controller: rules, maxLines: 6, style: const TextStyle(color: Colors.white70), decoration: const InputDecoration(labelText: '自定义使用规范', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), filled: true, fillColor: Color(0xFF292929))),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: Colors.white54))),
                const SizedBox(width: 8),
                FilledButton(onPressed: () async { settings.agentSystemPrompt = prompt.text; settings.agentUsageRules = rules.text; await SettingsService.save(settings); if (dialogContext.mounted) Navigator.pop(dialogContext); }, child: const Text('保存')),
              ]),
            ]),
        ),
      ),
    );
    prompt.dispose();
    rules.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _addInputHistory(text);

    // '/' 开头按命令处理：精确匹配则执行，否则直接丢弃（不把命令残片发给 AI）
    if (text.startsWith('/')) {
      final cmd = _palette.findExact(text.substring(1));
      _inputController.clear();
      cmd?.execute();
      return;
    }

    _inputController.clear();
    if (_isSending) {
      setState(() => _queuedTexts.add(text));
      return;
    }
    await _sendText(text);
  }

  void _addInputHistory(String text) {
    if (text.isEmpty) return;
    if (_inputHistory.isNotEmpty && _inputHistory.last == text) {
      _historyIndex = -1;
      _historyDraft = '';
      return;
    }
    _inputHistory.add(text);
    _historyIndex = -1;
    _historyDraft = '';
  }

  void _showPreviousInput() {
    if (_inputHistory.isEmpty) return;
    if (_historyIndex == -1) _historyDraft = _inputController.text;
    if (_historyIndex < _inputHistory.length - 1) _historyIndex++;
    _setInputText(_inputHistory[_inputHistory.length - 1 - _historyIndex]);
  }

  void _showNextInput() {
    if (_historyIndex == -1) return;
    if (_historyIndex > 0) {
      _historyIndex--;
      _setInputText(_inputHistory[_inputHistory.length - 1 - _historyIndex]);
    } else {
      _historyIndex = -1;
      _setInputText(_historyDraft);
      _historyDraft = '';
    }
  }

  void _setInputText(String text) {
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// 核心发送流程：追加用户消息并流式请求回复（输入发送与 /retry 共用）
  Future<void> _sendText(String text) async {
    if (_isSending) {
      _queuedTexts.add(text);
      return;
    }

    _conversation ??= ChatConversation(
      id: ChatStorageService.newConversationId(),
      title: text,
    );
    final conversationId = _conversation!.id;
    // 构建历史消息（不含当前用户消息）
    final history = <Map<String, String>>[];
    for (final msg in _messages) {
      if (msg.text.isEmpty || msg.local) continue;
      history.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': _historyContent(msg),
      });
    }


    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isSending = true;
    });
    _saveConversation();
    _scrollToBottom(force: true);

    // 添加空的 AI 消息用于流式填充
    setState(() {
      _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
    });

    try {
      // 重置 agent 对话并传入历史，避免与旧 popup 状态冲突
      AgentService.resetConversation();
      await for (final event in AgentService.chatStream(
        text,
        mode: 'auto',
        history: history,
        conversationId: conversationId,
      )) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case AgentRoundEvent():
              // 中间轮过程文字结束，插分隔线区分轮次
              if (_messages.last.text.trim().isNotEmpty || _messages.last.toolEvents.isNotEmpty) {
                _messages.last.streaming = false;
                _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
              }
            case AgentTokenEvent(:final text):
              _messages.last.text += text;
            case AgentQuestionEvent(:final questionId, :final questions):
              // 提问挂起：卡片显示在输入框上方，回答后经 _submitAgentAnswer 留痕
              if (questions.isNotEmpty) {
                setState(() {
                  _questionId = questionId;
                  _questionCtrl = AgentQuestionPanelController(questions: questions);
                });
              }
              case AgentToolEvent(:final id, :final name, :final running, :final error, :final details, :final changes):
              if (running) {
                // 工具调用属于新的执行轮次。若上一轮已经有文本，先切出独立气泡，
                // 避免工具返回的 diff 被渲染到最终回复的最底部。
                if (_messages.last.text.trim().isNotEmpty) {
                  _messages.last.streaming = false;
                  _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
                }
                _messages.last.toolEvents.add(_ToolEvent(
                  id,
                  name,
                  running: true,
                  parameters: details,
                ));
              } else {
                final index = _messages.last.toolEvents.lastIndexWhere(
                  (tool) => tool.id == id && tool.running,
                );
                if (index >= 0) {
                  final tool = _messages.last.toolEvents[index];
                  tool.running = false;
                  tool.error = error;
                  if (!error) tool.result = details;
                  if (error) tool.errorMessage = details?.toString();
                  if (!error && changes is List) {
                    for (final raw in changes.whereType<Map>()) {
                      final change = FileChangePreview.fromJson(Map<String, dynamic>.from(raw));
                      final existing = _messages.last.fileChanges.indexWhere((item) => item.path == change.path);
                      if (existing >= 0) _messages.last.fileChanges[existing] = change;
                      else _messages.last.fileChanges.add(change);
                      tool.changes.add(change);
                    }
                  }
                } else {
                  _messages.last.toolEvents.add(_ToolEvent(
                    id,
                    name,
                    running: false,
                    error: error,
                    parameters: details,
                    result: error ? null : details,
                    errorMessage: error ? details?.toString() : null,
                  ));
                }
              }
          }
        });
        _scrollToBottom();
      }
      if (mounted) {
        setState(() {
          _messages.last.streaming = false;
        });
      }
    } on AgentException catch (e) {
      if (!mounted) return;
      setState(() {
        final cancelled = e.message.toLowerCase().contains('cancel') ||
            e.message.toLowerCase().contains('abort');
        _messages.last.text = cancelled ? '已终止' : e.message;
        _messages.last.streaming = false;
        _messages.last.terminated = cancelled;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.last.text = '请求失败: $e';
        _messages.last.streaming = false;
        final message = e.toString().toLowerCase();
        if (message.contains('cancel') || message.contains('abort')) {
          _messages.last.text = '已终止';
          _messages.last.terminated = true;
        }
      });
    }

    if (mounted) {
      setState(() {
        _isSending = false;
        // 流已结束（完成/取消/断连）：收起未回答的提问卡片，questionId 已失效
        _dismissQuestionCard();
      });
    }
    _saveConversation();
    if (mounted && _queuedTexts.isNotEmpty) {
      final next = _queuedTexts.removeAt(0);
      await _sendText(next);
    }
  }

  String _historyContent(_ChatMessage msg) {
    if (msg.isUser || msg.fileChanges.isEmpty) return msg.text;
    final summary = msg.fileChanges.map((change) =>
        '[file change] ${change.operation}: ${change.path} (+${change.additions}/-${change.deletions})').join('\n');
    return '${msg.text}\n\n$summary';
  }

  /// 提交问题卡片答案：发送 user.answer → 气泡内留痕 → 收起卡片
  void _submitAgentAnswer() {
    final ctrl = _questionCtrl;
    if (ctrl == null || _questionId == null) return;
    _answerAgentQuestion(ctrl.questions, ctrl.answers, skipped: false);
  }

  /// 跳过当前提问：发送全空答案，LLM 侧视为未回答
  void _skipAgentQuestion() {
    final ctrl = _questionCtrl;
    if (ctrl == null || _questionId == null) return;
    _answerAgentQuestion(ctrl.questions, ctrl.skippedAnswers, skipped: true);
  }

  void _answerAgentQuestion(List<AgentQuestion> questions, List<List<String>> answers, {required bool skipped}) {
    final questionId = _questionId!;
    setState(() {
      _dismissQuestionCard();
      // 留痕挂在对应的 ask_user_question 工具行下面（与 FileChangesPanel 同级）：
      // user.question 一定发生在该工具 tool.start 之后、tool.result 之前
      final index = _messages.lastIndexWhere((m) => !m.isUser && m.toolEvents.any((t) => t.running && t.name == 'ask_user_question'));
      if (index >= 0) {
        final toolIndex = _messages[index].toolEvents.lastIndexWhere((t) => t.running && t.name == 'ask_user_question');
        _messages[index].toolEvents[toolIndex].questionPanels.add(_QuestionPanel(questions: questions, answers: answers, skipped: skipped));
      }
    });
    AgentService.answerQuestion(questionId, answers);
    _saveConversation();
  }

  /// 收起提问卡片（须在 setState 内调用）；卡片 controller 持有 text 输入框，需 dispose
  void _dismissQuestionCard() {
    _questionCtrl?.dispose();
    _questionCtrl = null;
    _questionId = null;
  }

  void _scrollToBottom({bool force = false}) {
    // 在当前帧提交前判断是否跟随，避免内容增长后 maxScrollExtent 变化导致
    // 原本在底部的用户被误判为“已滚动到前面”。
    final shouldFollow = force ||
        !_scrollController.hasClients ||
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && shouldFollow) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_isSending &&
        key == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed) {
      AgentService.cancelCurrent();
      return KeyEventResult.handled;
    }

    // 命令面板可见时，导航键优先于输入框默认行为
    if (_palette.visible) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _palette.movePrevious();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _palette.moveNext();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _palette.dismiss();
        return KeyEventResult.handled;
      }
      final isConfirm = key == LogicalKeyboardKey.tab ||
          (key == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed);
      if (isConfirm) {
        _confirmCommand();
        return KeyEventResult.handled;
      }
    }

    // Agent 提问卡片挂起时接管导航键（显式唤起的命令面板优先级更高，见上）。
    // 输入框正在打字时不接管 ↑↓/Enter，避免拦截用户排队发送的消息；Esc 始终可跳过提问。
    if (_questionCtrl != null) {
      if (key == LogicalKeyboardKey.escape) {
        _skipAgentQuestion();
        return KeyEventResult.handled;
      }
      if (_inputController.text.isEmpty) {
        if (key == LogicalKeyboardKey.arrowUp) {
          _questionCtrl!.navigate(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _questionCtrl!.navigate(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          if (_questionCtrl!.confirmCurrent()) _submitAgentAnswer();
          return KeyEventResult.handled;
        }
      }
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _showPreviousInput();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _showNextInput();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _sendMessage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── 消息列表 ──────────────────────────────────────────────────────────

  Widget _buildChatList() {
    return Theme(
      data: _listTheme,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _messages.length,
          itemBuilder: (_, index) {
            return _buildMessageBubble(_messages[index]);
          },
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    // step/turn 事件可能创建没有文本和内容的占位消息；完成后不应留下空白气泡。
    if (!msg.isUser &&
        !msg.streaming &&
        msg.text.trim().isEmpty &&
        msg.toolEvents.isEmpty &&
        msg.fileChanges.isEmpty) {
      return const SizedBox.shrink();
    }
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MessageStatusDot(status: MessageStatus.user),
            Expanded(
              child: Text(
                msg.text,
                style: TextStyle(
                  color: _bubbleText,
                  fontSize: 13,
                  height: 1.4,
                  fontFamily: _fontFamily,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tool in msg.toolEvents)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedOpacity(opacity: tool.running ? (_toolBlinkOn ? 1 : 0.2) : 1, duration: const Duration(milliseconds: 180), child: Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: Icon(Icons.circle, size: 7, color: Colors.lightBlueAccent))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_toolDisplayName(tool.name), style: TextStyle(color: _bubbleText, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: _fontFamily)),
                // ask_user_question 的参数 dump 由问答留痕卡替代
                if (tool.name != 'ask_user_question' && (tool.parameters != null || tool.result != null || tool.errorMessage != null))
                  Text(_formatToolDetails(tool.name, tool.parameters, null, error: tool.errorMessage), maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: _fontFamily)),
                if (tool.errorMessage != null) Text(tool.errorMessage!, maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: _fontFamily)),
                if (tool.changes.isNotEmpty) FileChangesPanel(changes: tool.changes),
                // ask_user_question 的问答留痕卡（与 diff 面板同级）
                for (final panel in tool.questionPanels)
                  QuestionRecordCard(
                    questions: panel.questions,
                    answers: panel.answers,
                    skipped: panel.skipped,
                  ),
              ])),
            ]),
          ),
        // 正文气泡：只在有文本或（等待占位且还没有工具行）时渲染。
        // fileChanges/diff 与问答卡都挂在工具行下，正文区只剩状态点时不渲染，
        // 否则会出现孤立圆点（工具行之间的 completed 绿点/processing 灰点）
        if (msg.text.trim().isNotEmpty || (msg.streaming && msg.toolEvents.isEmpty))
          Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MessageStatusDot(
                status: msg.terminated
                    ? MessageStatus.terminated
                    : msg.streaming
                        ? MessageStatus.processing
                        : MessageStatus.completed,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MarkdownBody(
            data: msg.streaming ? '${msg.text}▌' : msg.text,
            selectable: false,
            builders: {
              // 只接管代码块文字颜色（含外边距与横向滚动）；背景/圆角/边框仍走样式表
              'pre': _PreTextBuilder(
                TextStyle(
                  color: _codeBlockText,
                  fontSize: 13,
                  fontFamily: _codeFont,
                  fontFamilyFallback: [_fontFamily],
                  ),
              ),
            },
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(
                color: _bubbleText,
                fontSize: 14,
                height: 1.4,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w400,
                fontFamily: _fontFamily,
              ),
              h1: TextStyle(
                color: _bubbleText,
                fontSize: 17,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              h1Padding: const EdgeInsets.only(top: 14, bottom: 6),
              h2: TextStyle(
                color: _bubbleText,
                fontSize: 15,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              h2Padding: const EdgeInsets.only(top: 12, bottom: 5),
              h3: TextStyle(
                color: _bubbleText,
                fontSize: 14,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              h3Padding: const EdgeInsets.only(top: 10, bottom: 4),
              code: TextStyle(
                color: _codeText,
                fontSize: 13,
                fontFamily: _codeFont,
                fontFamilyFallback: [_fontFamily],
              ),
              codeblockDecoration: BoxDecoration(
                color: _codeBlockBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              a: TextStyle(
                color: _linkText,
                letterSpacing: 0.8,
                fontFamily: _fontFamily,
              ),
              blockquoteDecoration: BoxDecoration(
                color: _bubbleText.withValues(alpha: 0.05),
                border: Border(
                  left: BorderSide(color: _dividerColor, width: 3),
                ),
              ),
              blockquotePadding:
                  const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 8),
              tableHead: TextStyle(
                color: _bubbleText,
                fontSize: 13,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              tableBody: TextStyle(
                color: _bubbleText,
                fontSize: 13,
                letterSpacing: 0.8,
                fontFamily: _fontFamily,
              ),
              tablePadding: const EdgeInsets.symmetric(vertical: 16),
              tableBorder: TableBorder.all(color: _dividerColor, width: 1),
              tableCellsPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              tableCellsDecoration: const BoxDecoration(),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: _dividerColor, width: 1),
                ),
              ),
            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 临时隐藏：复制 / 重新生成按钮
        // if (!msg.streaming)
        //   Padding(
        //     padding: const EdgeInsets.only(left: 12, right: 12, top: 6),
        //     child: Row(
        //       children: [
        //         _buildActionButton('assets/svg/复制.svg', '复制', () {
        //           Clipboard.setData(ClipboardData(text: msg.text));
        //         }),
        //         const SizedBox(width: 14),
        //         _buildActionButton('assets/svg/重新.svg', '重新生成', () {
        //           // TODO: 重新生成
        //         }),
        //       ],
        //     ),
        //   ),
      ],
    );
  }

  Widget _buildActionButton(
      String svgAsset, String label, VoidCallback onTap) {
    final isHovered = _hoveredAction == label;
    final isSelected = _selectedAction == label;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredAction = label),
      onExit: (_) => setState(() => _hoveredAction = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedAction = label);
          onTap();
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) setState(() => _selectedAction = null);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected
                ? _chipActiveBg
                : isHovered
                    ? _chipActiveBg.withValues(alpha: 0.4)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SvgPicture.asset(
            svgAsset,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              isSelected || isHovered ? _chipActiveText : _statusText,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

}

/// 代码块文字：只重写 visitText 换颜色，块的外层样式仍由样式表渲染
/// （flutter_markdown 没有单独的代码块文字样式字段，code 一个样式管行内+整块）
class _PreTextBuilder extends MarkdownElementBuilder {
  _PreTextBuilder(this.style);

  final TextStyle style;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().firstWhere(
          (child) => child.tag == 'code',
          orElse: () => element,
        );
    final classes = code?.attributes['class'] ?? '';
    final language = classes.startsWith('language-')
        ? classes.substring('language-'.length)
        : '';
    final source = element.textContent;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: const Color(0xFF18212B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (language.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(language, style: style.copyWith(fontSize: 11, color: Colors.white54)),
                ),
              const Spacer(),
              _CodeCopyButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: source)),
              ),
            ],
          ),
          if (language.isNotEmpty)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 10,
              endIndent: 10,
              color: Color(0x265E7185),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Text(source, style: style),
          ),
        ],
      ),
    );
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(10),
      child: Text(text.text, style: style),
    );
  }
}

class _CodeCopyButton extends StatefulWidget {
  const _CodeCopyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CodeCopyButton> createState() => _CodeCopyButtonState();
}

class _CodeCopyButtonState extends State<_CodeCopyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 30,
          height: 30,
          alignment: Alignment.center,
          color: _hovered ? const Color(0x265E7185) : Colors.transparent,
          child: const Icon(Icons.copy, size: 15, color: Colors.white60),
        ),
      ),
    );
  }
}
