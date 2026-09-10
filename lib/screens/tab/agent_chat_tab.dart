import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/agent_service.dart';
import '../../services/menu_window_signals.dart';
import '../../widgets/typing_indicator.dart';

class AgentChatTab extends StatefulWidget {
  const AgentChatTab({super.key});

  @override
  State<AgentChatTab> createState() => _AgentChatTabState();
}

class _AgentChatTabState extends State<AgentChatTab> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _messages = <_ChatMessage>[];
  String? _hoveredAction;
  String? _selectedAction;
  bool _isSending = false;

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
    // 每次窗口被显示时，输入框自动获得焦点
    menuWindowShown.addListener(_focusInput);
  }

  void _focusInput() {
    if (!_isSending) _inputFocus.requestFocus();
  }

  @override
  void dispose() {
    menuWindowShown.removeListener(_focusInput);
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
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
  static const _bubbleText = Color(0xFFD4D4D4);
  static const _statusText = Colors.white;
  static const _dividerColor = Color(0xFF3A3A3A);

  /// Markdown 元素配色：代码与链接区别于正文白色
  static const _codeText = Color(0xFF81C784);
  static const _codeBlockBg = Color(0xFF101215);
  static const _linkText = Color(0xFF64B5F6);

  /// 聊天统一字体：更纱黑体——西文为内嵌等宽，中文严格两倍宽，终端格子感
  static const _fontFamily = 'Sarasa Mono SC';

  // ─── 发送消息 ──────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    // 构建历史消息（不含当前用户消息）
    final history = <Map<String, String>>[];
    for (final msg in _messages) {
      if (msg.text.isEmpty) continue;
      history.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.text,
      });
    }

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom(force: true);

    // 添加空的 AI 消息用于流式填充
    setState(() {
      _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
    });

    try {
      // 重置 agent 对话并传入历史，避免与旧 popup 状态冲突
      AgentService.resetConversation();
      await for (final chunk in AgentService.chatStream(
        text,
        mode: 'auto',
        history: history,
      )) {
        if (!mounted) return;
        setState(() {
          _messages.last.text += chunk;
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
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _sendMessage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── 构建 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
    return Focus(
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
    );
  }

  // ─── 底栏 ──────────────────────────────────────────────────────────────

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
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(
                color: _bubbleText,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w400,
                fontFamily: _fontFamily,
              ),
              h1: TextStyle(
                color: _bubbleText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              h2: TextStyle(
                color: _bubbleText,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              h3: TextStyle(
                color: _bubbleText,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              code: TextStyle(
                color: _codeText,
                fontSize: 13,
                fontFamily: _fontFamily,
              ),
              codeblockPadding: const EdgeInsets.all(10),
              codeblockDecoration: BoxDecoration(
                color: _codeBlockBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              a: TextStyle(
                color: _linkText,
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
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
              tableBody: TextStyle(
                color: _bubbleText,
                fontSize: 13,
                fontFamily: _fontFamily,
              ),
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
  _ChatMessage({required this.text, required this.isUser, this.streaming = false});

  String text;
  final bool isUser;
  bool streaming;
}
