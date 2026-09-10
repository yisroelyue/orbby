import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;

import '../services/agent_service.dart';
import '../services/chat_command.dart';
import '../services/chat_storage_service.dart';
import '../services/file_undo_service.dart';
import '../services/menu_window_signals.dart';
import '../widgets/command_palette.dart';
import '../widgets/frosted_panel.dart';
import '../widgets/session_picker_dialog.dart';
import '../widgets/typing_indicator.dart';

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

  /// 当前会话（持久化）；null = 新对话尚未落盘，首轮发送时创建
  ChatConversation? _conversation;
  Future<void> _saveChain = Future<void>.value();

  /// '/' 命令面板：命令注册表见 [_buildCommands]
  late final _palette = CommandPaletteController(commands: _buildCommands());

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
    WidgetsBinding.instance.addObserver(this);
    HomeScreen.menuChannel.invokeMethod('ready');
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
    WidgetsBinding.instance.removeObserver(this);
    menuWindowShown.removeListener(_focusInput);
    _inputController.removeListener(_onInputChanged);
    _palette.dispose();
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
  static const _codeText = Color(0xFF81C784);

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
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(-10, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
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
    final showTyping = _isSending && !_messages.last.streaming;
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
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            controller: _inputController,
            focusNode: _inputFocus,
            minLines: 1,
            maxLines: 10,
            enabled: !_isSending,
            cursorColor: Colors.white,
            style: TextStyle(
                color: _inputText,
                fontSize: 14,
                fontFamily: _fontFamily),
            decoration: InputDecoration(
              hintText: _isSending ? '' : '描述你的需求或想法',
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
              suffixIcon: _isSending
                  ? const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: TypingIndicator(),
                    )
                  : Padding(
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
        name: 'clear',
        description: '清空当前对话（旧会话保留在历史中）',
        execute: () {
          if (!mounted) return;
          // 旧会话文件保留，下次发送创建新会话
          setState(() {
            _conversation = null;
            _messages.clear();
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
        name: 'apps',
        description: '打开应用中心',
        execute: () => HomeScreen.menuChannel.invokeMethod('open_app_center'),
      ),
      ChatCommand(
        name: 'settings',
        description: '打开设置窗口',
        execute: () => HomeScreen.menuChannel.invokeMethod('open_settings'),
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

  /// 当前对话落盘（~/.orbby/claude_task/task）；空对话不创建文件。
  /// 首轮发送时创建会话，标题取第一条用户消息。
  /// 保存请求串行执行（_saveChain），避免两次快照交错落盘；
  /// 链内吞错——一环失败不能毒化后续所有保存。
  Future<void> _saveConversation() {
    _saveChain = _saveChain.then((_) async {
      try {
        final msgs = <Map<String, String>>[
          for (final m in _messages)
            // local 消息（命令结果）是瞬时提示，不落盘：
            // 否则重载会话后 local 标志丢失，会混进下次发送的 history
            if (m.text.isNotEmpty && !m.local)
              {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
        ];
        if (msgs.isEmpty) return;
        _conversation ??= ChatConversation(
          id: '${DateTime.now().millisecondsSinceEpoch}',
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
            ),
        ]);
    });
    _scrollToBottom(force: true);
  }

  // ─── 发送消息 ──────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    // '/' 开头按命令处理：精确匹配则执行，否则直接丢弃（不把命令残片发给 AI）
    if (text.startsWith('/')) {
      final cmd = _palette.findExact(text.substring(1));
      _inputController.clear();
      cmd?.execute();
      return;
    }

    _inputController.clear();
    await _sendText(text);
  }

  /// 核心发送流程：追加用户消息并流式请求回复（输入发送与 /retry 共用）
  Future<void> _sendText(String text) async {
    if (_isSending) return;

    // 构建历史消息（不含当前用户消息）
    final history = <Map<String, String>>[];
    for (final msg in _messages) {
      if (msg.text.isEmpty || msg.local) continue;
      history.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.text,
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
      )) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case AgentRoundEvent():
              // 中间轮过程文字结束，插分隔线区分轮次
              if (_messages.last.text.isNotEmpty) {
                _messages.last.text += '\n\n---\n\n';
              }
            case AgentTokenEvent(:final text):
              _messages.last.text += text;
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
        _messages.last.text = e.message;
        _messages.last.streaming = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.last.text = '请求失败: $e';
        _messages.last.streaming = false;
      });
    }

    if (mounted) setState(() => _isSending = false);
    _saveConversation();
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (!force) {
          final pos = _scrollController.position;
          if (pos.pixels < pos.maxScrollExtent - 50) return;
        }
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
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 12, top: 3, bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(14),
            ),
          ),
          child: Text(
            msg.text,
            style: TextStyle(
              color: _bubbleText,
              fontSize: 13,
              fontFamily: _fontFamily,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: MarkdownBody(
            data: msg.streaming ? '${msg.text}▌' : msg.text,
            selectable: false,
            builders: {
              // 只接管代码块文字颜色（含外边距与横向滚动）；背景/圆角/边框仍走样式表
              'pre': _PreTextBuilder(
                TextStyle(
                  color: _codeBlockText,
                  fontSize: 12,
                  fontFamily: _codeFont,
                  fontFamilyFallback: [_fontFamily],
                ),
              ),
            },
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(
                color: _bubbleText,
                fontSize: 12,
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
                fontSize: 12,
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
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              tableBody: TextStyle(
                color: _bubbleText,
                fontSize: 12,
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

class _ChatMessage {
  _ChatMessage({required this.text, required this.isUser, this.streaming = false, this.local = false});

  String text;
  final bool isUser;
  bool streaming;
  final bool local;
}

/// 代码块文字：只重写 visitText 换颜色，块的外层样式仍由样式表渲染
/// （flutter_markdown 没有单独的代码块文字样式字段，code 一个样式管行内+整块）
class _PreTextBuilder extends MarkdownElementBuilder {
  _PreTextBuilder(this.style);

  final TextStyle style;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(10),
      child: Text(text.text, style: style),
    );
  }
}
