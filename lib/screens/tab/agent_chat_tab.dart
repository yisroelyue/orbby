import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../config/platform.dart';
import '../../config/settings.dart';
import '../../services/agent_service.dart';
import '../../widgets/typing_indicator.dart';

class AgentChatTab extends StatefulWidget {
  const AgentChatTab({super.key, required this.isDark});

  final bool isDark;

  @override
  State<AgentChatTab> createState() => _AgentChatTabState();
}

class _AgentChatTabState extends State<AgentChatTab> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _messages = <_ChatMessage>[];
  String? _hoveredAction;
  String? _selectedAction;
  bool _isSending = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  // ─── 颜色 ──────────────────────────────────────────────────────────────

  Color get _scaffoldBg =>
      widget.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  Color get _inputBg =>
      widget.isDark ? const Color(0xFF2A2A2A) : const Color(0x0D000000);
  Color get _inputText =>
      widget.isDark ? const Color(0xB3FFFFFF) : const Color(0xFF333333);
  Color get _inputHint =>
      widget.isDark ? const Color(0x4DFFFFFF) : const Color(0xFF888888);
  Color get _chipActiveBg =>
      widget.isDark ? const Color(0x26FFFFFF) : const Color(0x14000000);
  Color get _chipActiveText =>
      widget.isDark ? const Color(0xB3FFFFFF) : const Color(0xFF333333);
  Color get _chipInactiveText =>
      widget.isDark ? const Color(0x4DFFFFFF) : const Color(0xFF999999);
  Color get _headerText =>
      widget.isDark ? Colors.white : const Color(0xFF333333);
  Color get _userBubble =>
      widget.isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);
  Color get _bubbleText => widget.isDark ? Colors.white : const Color(0xFF333333);
  Color get _statusText =>
      widget.isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  Color get _dividerColor =>
      widget.isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);

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
      decoration: BoxDecoration(
        color: _scaffoldBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: isEmpty ? _buildWelcomeScreen() : _buildChatArea(),
    );
  }

  // ─── 欢迎页 ─────────────────────────────────────────────────────────────

  Widget _buildWelcomeScreen() {
    return Column(
      children: [
        _buildModelLabel(),
        const Spacer(flex: 2),
        Text(
          '我可以为你做些什么？',
          style: TextStyle(
            color: _headerText,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeInputArea(),
              const SizedBox(height: 16),
              _buildSuggestionItem(
                'assets/png/agentHint/1.png',
                '开始使用 Orbby 助手，查看常用功能',
                '你好，请介绍你的功能。',
              ),
              const SizedBox(height: 12),
              _buildSuggestionItem(
                'assets/png/agentHint/2.svg',
                '探索创意灵感',
                '给我一些创意灵感和建议。',
              ),
              const SizedBox(height: 12),
              _buildSuggestionItem(
                'assets/png/agentHint/3.svg',
                '编写代码，测试用例，执行脚本',
                '请帮我写一段代码。',
              ),
            ],
          ),
        ),
        const Spacer(flex: 3),
      ],
    );
  }

  Widget _buildSuggestionItem(String iconPath, String title, String prompt) {
    final isHovered = _hoveredAction == title;
    final isSvg = iconPath.endsWith('.svg');
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredAction = title),
      onExit: (_) => setState(() => _hoveredAction = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _inputController.text = prompt;
          _sendMessage();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isHovered
                ? _chipActiveBg.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isSvg
                  ? SvgPicture.asset(iconPath, width: 22, height: 22)
                  : Image.asset(iconPath, width: 22, height: 22),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: _chipInactiveText,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 聊天区域 ──────────────────────────────────────────────────────────

  Widget _buildChatArea() {
    final showTyping = _isSending && !_messages.last.streaming;
    return Column(
      children: [
        _buildModelLabel(),
        const SizedBox(height: 4),
        Expanded(child: _buildChatList()),
        if (showTyping) ...[
          const SizedBox(height: 8),
          const TypingIndicator(),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        _buildInputArea(),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildModelLabel() {
    return FutureBuilder(
      future: _getModelName(),
      builder: (_, snap) {
        final modelStr = snap.data ?? '';
        if (modelStr.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _chipActiveBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                modelStr,
                style: TextStyle(
                  color: _statusText,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String> _getModelName() async {
    final s = await SettingsService.load();
    return s.model.isEmpty
        ? PlatformConfig.defaultChatModel(s.platform)
        : s.model;
  }

  // ─── 输入框 ─────────────────────────────────────────────────────────────

  Widget _buildWelcomeInputArea() {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: _inputController,
        minLines: 2,
        maxLines: 4,
        enabled: !_isSending,
        style: TextStyle(color: _inputText, fontSize: 14),
        decoration: InputDecoration(
          hintText: _isSending ? '' : '描述你的需求或想法',
          hintStyle: TextStyle(color: _inputHint, fontSize: 14),
          isDense: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          filled: true,
          fillColor: _inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _isSending
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: TypingIndicator(),
                )
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: SvgPicture.asset('assets/svg/发送.svg',
                        width: 24, height: 24),
                    onPressed: _sendMessage,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: _inputController,
        minLines: 2,
        maxLines: 4,
        enabled: !_isSending,
        style: TextStyle(color: _inputText, fontSize: 14),
        decoration: InputDecoration(
          hintText: _isSending ? '' : '描述你的需求或想法',
          hintStyle: TextStyle(color: _inputHint, fontSize: 15),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          filled: true,
          fillColor: _inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _isSending
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: TypingIndicator(),
                )
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: SvgPicture.asset('assets/svg/发送.svg',
                        width: 24, height: 24),
                    onPressed: _sendMessage,
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
      data: ThemeData(
        brightness: widget.isDark ? Brightness.dark : Brightness.light,
        scrollbarTheme: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(0),
        ),
      ),
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
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.text,
            style: TextStyle(color: _bubbleText, fontSize: 13),
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
                fontWeight: FontWeight.w400,
                fontFamily: 'Microsoft YaHei',
              ),
              h1: TextStyle(
                color: _bubbleText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Microsoft YaHei',
              ),
              h2: TextStyle(
                color: _bubbleText,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Microsoft YaHei',
              ),
              h3: TextStyle(
                color: _bubbleText,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'Microsoft YaHei',
              ),
              code: TextStyle(
                color: _bubbleText,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              codeblockDecoration: BoxDecoration(
                color: _bubbleText.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              a: TextStyle(
                color: _bubbleText,
                fontFamily: 'Microsoft YaHei',
              ),
              blockquoteDecoration: BoxDecoration(
                color: _bubbleText.withValues(alpha: 0.05),
                border: Border(
                  left: BorderSide(color: _dividerColor, width: 3),
                ),
              ),
              blockquotePadding:
                  const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 8),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: _dividerColor, width: 1),
                ),
              ),
            ),
          ),
        ),
        if (!msg.streaming)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 6),
            child: Row(
              children: [
                _buildActionButton('assets/svg/复制.svg', '复制', () {
                  Clipboard.setData(ClipboardData(text: msg.text));
                }),
                const SizedBox(width: 14),
                _buildActionButton('assets/svg/重新.svg', '重新生成', () {
                  // TODO: 重新生成
                }),
              ],
            ),
          ),
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
