import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../config/constants.dart';
import '../config/settings.dart';
import '../widgets/agent_chat_panel.dart';
import '../widgets/typing_indicator.dart';

class AgentChatPopup extends StatefulWidget {
  const AgentChatPopup({super.key});

  static const popupChannel = WindowMethodChannel(
    'orbby_agent_chat_popup_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<AgentChatPopup> createState() => _AgentChatPopupState();
}

class _AgentChatPopupState extends State<AgentChatPopup>
    with TickerProviderStateMixin, WindowListener {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _messages = <_ChatMessage>[];
  AgentChatPalette _theme = AgentChatColors.light;
  String _themeName = 'light';
  String _mode = 'accept';
  String? _selectedAction;
  String? _hoveredAction;
  bool _isSending = false;
  bool _isHoveredClear = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  void onWindowFocus() {
    AgentChatPopup.popupChannel.invokeMethod('popup_focus_changed', {'focused': true});
  }

  @override
  void onWindowBlur() {
    AgentChatPopup.popupChannel.invokeMethod('popup_focus_changed', {'focused': false});
  }

  Future<void> _init() async {
    final c = await WindowController.fromCurrentEngine();
    c.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'set_data':
          final args = call.arguments as Map;
          final w = (args['width'] as num?)?.toDouble() ?? 400;
          final h = (args['height'] as num?)?.toDouble() ?? 500;
          final l = (args['left'] as num?)?.toDouble() ?? 0;
          final t = (args['top'] as num?)?.toDouble() ?? 0;
          final theme = args['theme'] as String? ?? 'light';
          await windowManager.setMinimumSize(const Size(400, 500));
          await windowManager.setMaximumSize(const Size(3840, 2160));
          await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
          await windowManager.show();
          if (mounted) {
            setState(() {
              _theme = AgentChatColors.of(theme);
              _themeName = theme;
            });
          }
          return;
        case 'clear_messages':
          setState(() => _messages.clear());
          return;
        case 'remove_last_message':
          if (_messages.isNotEmpty) {
            setState(() => _messages.removeLast());
          }
          return;
        case 'focus_window':
          await windowManager.show();
          await windowManager.focus();
          return;
        case 'add_message':
          final args = call.arguments as Map;
          final text = args['text'] as String? ?? '';
          final isUser = args['isUser'] as bool? ?? true;
          final streaming = args['streaming'] as bool? ?? false;
          if (text.isNotEmpty || streaming) {
            setState(() {
              _messages.add(_ChatMessage(
                text: text,
                isUser: isUser,
                streaming: streaming,
              ));
              if (streaming) {
                // 流式消息替代 loading 指示器
                _isSending = false;
              } else {
                _isSending = isUser;
              }
            });
            _scrollToBottom();
          }
          return;
        case 'append_stream_chunk':
          final args = call.arguments as Map;
          final chunk = args['text'] as String? ?? '';
          if (chunk.isNotEmpty && _messages.isNotEmpty) {
            setState(() {
              _messages.last.text += chunk;
            });
            _scrollToBottom();
          }
          return;
        case 'stream_end':
          if (_messages.isNotEmpty) {
            setState(() {
              _messages.last.streaming = false;
            });
          }
          return;
        case 'stream_error':
          final args = call.arguments as Map;
          final error = args['error'] as String? ?? '请求失败';
          // 移除空的流式消息，显示错误
          if (_messages.isNotEmpty && _messages.last.streaming) {
            setState(() {
              _messages.removeLast();
              _messages.add(_ChatMessage(text: error, isUser: false));
              _isSending = false;
            });
          }
          return;
        default:
          throw UnimplementedError('Not implemented: ${call.method}');
      }
    });

    final args = _parseArgs(c.arguments);
    final w = (args['width'] as num?)?.toDouble() ?? 400;
    final h = (args['height'] as num?)?.toDouble() ?? 500;
    final l = (args['left'] as num?)?.toDouble() ?? 0;
    final t = (args['top'] as num?)?.toDouble() ?? 0;
    final theme = args['theme'] as String? ?? 'light';
    await windowManager.setMinimumSize(const Size(400, 500));
    await windowManager.setMaximumSize(const Size(3840, 2160));
    await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
    if (args['hidden'] != true) {
      await windowManager.show();
    }
    if (mounted) {
      setState(() {
        _theme = AgentChatColors.of(theme);
        _themeName = theme;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Map<String, dynamic> _parseArgs(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  // ─── 发送消息 ────────────────────────────────────────────────────────────

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    AgentChatPopup.popupChannel.invokeMethod('popup_send_message', {
      'text': text,
      'mode': _mode,
    });
    _inputController.clear();
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

  void _closePopup() {
    AgentChatPopup.popupChannel.invokeMethod('popup_close');
  }

  // ─── 构建 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = _themeName == 'dark';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        fontFamily: 'NotoSansSC',
      ),
      home: Scaffold(
        backgroundColor: _theme.scaffoldBg,
        body: DragToResizeArea(
          child: Container(
            padding: const EdgeInsets.all(12),
            color: _theme.scaffoldBg,
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 4),
                Expanded(child: _buildChatList()),
                const SizedBox(height: 4),
                _buildContextLabel(),
                const SizedBox(height: 4),
                _buildInputArea(),
                const SizedBox(height: 6),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final isDark = _themeName == 'dark';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Row(
        children: [
          Image.asset(PetConfig.logoSprite, width: 22, height: 22),
          const SizedBox(width: 8),
          Text(
            'Orbby Agent',
            style: TextStyle(
              color: _theme.headerText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // 主题切换
          _buildHeaderButton(
            tooltip: isDark ? '明亮模式' : '暗黑模式',
            icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            onTap: () async {
              final newTheme = isDark ? 'light' : 'dark';
              setState(() {
                _themeName = newTheme;
                _theme = AgentChatColors.of(newTheme);
              });
              final s = await SettingsService.load();
              s.agentChatPopupTheme = newTheme;
              await SettingsService.save(s);
            },
          ),
          const SizedBox(width: 4),
          // 最小化
          _buildHeaderButton(
            tooltip: '最小化',
            icon: Icons.minimize_rounded,
            onTap: () => windowManager.minimize(),
          ),
          const SizedBox(width: 4),
          // 最大化/还原
          _buildHeaderButton(
            tooltip: _isMaximized ? '还原' : '最大化',
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            onTap: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
              setState(() => _isMaximized = !_isMaximized);
            },
          ),
          const SizedBox(width: 4),
          // 关闭
          _buildHeaderButton(
            tooltip: '关闭',
            icon: Icons.close_rounded,
            onTap: _closePopup,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: _theme.statusText),
          ),
        ),
      ),
    );
  }

  // ─── 输入区（从 AgentChatPanel 迁移） ────────────────────────────────────

  Widget _buildInputArea() {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: _inputController,
        minLines: 1,
        maxLines: 4,
        enabled: !_isSending,
        style: TextStyle(color: _theme.inputText, fontSize: 15),
        decoration: InputDecoration(
          hintText: _isSending ? '' : '输入消息...',
          hintStyle: TextStyle(color: _theme.inputHint),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          filled: true,
          fillColor: _theme.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _isSending
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: TypingIndicator(),
                )
              : IconButton(
                  icon: Icon(Icons.send_rounded,
                      size: 18, color: _theme.chipActiveText),
                  onPressed: _sendMessage,
                ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          _buildModeChip('accept'),
          const SizedBox(width: 6),
          _buildModeChip('plan'),
          const SizedBox(width: 6),
          _buildModeChip('auto'),
          const Spacer(),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveredClear = true),
            onExit: (_) => setState(() => _isHoveredClear = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                AgentChatPopup.popupChannel
                    .invokeMethod('popup_clear_context');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isHoveredClear
                      ? _chipHoverBg
                      : _theme.chipActiveBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'clear',
                  style: TextStyle(
                    color: _isHoveredClear
                        ? _theme.chipActiveText
                        : _theme.chipInactiveText,
                    fontSize: 13,fontWeight: FontWeight.w600
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label) {
    final isActive = _mode == label;
    return GestureDetector(
      onTap: () => setState(() => _mode = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? _theme.chipActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? _theme.chipActiveText : _theme.chipInactiveText,
            fontSize: 13,fontWeight: FontWeight.w700
          ),
        ),
      ),
    );
  }

  Color get _chipHoverBg {
    return _theme.chipActiveBg.withValues(
      alpha: _themeName == 'dark' ? 0.45 : 0.20,
    );
  }

  // ─── Context 标签（消息列表上方） ─────────────────────────────────────────

  Widget _buildContextLabel() {
    final chars = _messages.fold<int>(0, (sum, m) => sum + m.text.length);
    final sizeStr = chars >= 1024
        ? '${(chars / 1024).toStringAsFixed(chars >= 10240 ? 0 : 1)}k'
        : '${chars}b';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'context: $sizeStr',
          style: TextStyle(color: _theme.statusText, fontSize: 11),
        ),
      ),
    );
  }


  // ─── 消息列表 ────────────────────────────────────────────────────────────

  bool get _hasActiveStream {
    return _messages.isNotEmpty && _messages.last.streaming;
  }

  Widget _buildChatList() {
    if (_messages.isEmpty && !_isSending) {
      return Center(
        child: Text(
          '暂无消息',
          style: TextStyle(color: _theme.emptyText, fontSize: 13),
        ),
      );
    }
    // 有流式消息时不显示额外 loading
    final showTyping = _isSending && !_hasActiveStream;
    return Theme(
      data: ThemeData(
        brightness:
            _themeName == 'dark' ? Brightness.dark : Brightness.light,
        scrollbarTheme: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(0),
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _messages.length + (showTyping ? 1 : 0),
        itemBuilder: (_, index) {
          if (showTyping && index == _messages.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: TypingIndicator(),
            );
          }
          return _buildMessageBubble(_messages[index]);
        },
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
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: _theme.userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.text,
            style: TextStyle(color: _theme.bubbleText, fontSize: 13),
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
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: _theme.bubbleText, fontSize: 16,fontWeight: FontWeight.w400),
              h1: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              h2: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
              h3: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
              h4: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
              h5: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
              h6: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
              code: TextStyle(
                color: _theme.bubbleText,
                fontSize: 15,
                fontFamily: 'monospace',
              ),
              codeblockDecoration: BoxDecoration(
                color: _theme.bubbleText.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              a: TextStyle(color: _theme.bubbleText),
              blockquoteDecoration: BoxDecoration(
                color: _theme.bubbleText.withValues(alpha: 0.05),
                border: Border(
                  left: BorderSide(
                    color: _theme.dividerColor,
                    width: 3,
                  ),
                ),
              ),
              blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 8),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: _theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildActionButton('assets/svg/复制.svg', '复制', () {
                Clipboard.setData(ClipboardData(text: msg.text));
              }),
              const SizedBox(width: 14),
              _buildActionButton('assets/svg/重新.svg', '重新生成', () {
                AgentChatPopup.popupChannel.invokeMethod('agent_regenerate');
              }),
              const SizedBox(width: 14),
              _buildActionButton('assets/svg/more.svg', '更多', () {
                // TODO: 更多操作
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
                ? _theme.chipActiveBg
                : isHovered
                    ? _theme.chipActiveBg.withValues(alpha: 0.4)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SvgPicture.asset(
            svgAsset,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              isSelected || isHovered
                  ? _theme.chipActiveText
                  : _theme.statusText.withValues(alpha: 1),
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
