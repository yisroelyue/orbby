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

class _AgentChatPopupState extends State<AgentChatPopup> with TickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  AgentChatPalette _theme = AgentChatColors.light;
  String _themeName = 'light';
  String? _selectedAction;
  String? _hoveredAction;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
          await windowManager.setMinimumSize(Size(w, h));
          await windowManager.setMaximumSize(Size(w, h));
          await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
          await windowManager.show();
          if (mounted) setState(() { _theme = AgentChatColors.of(theme); _themeName = theme; });
          return;
        case 'clear_messages':
          setState(() => _messages.clear());
          return;
        case 'remove_last_message':
          if (_messages.isNotEmpty) {
            setState(() => _messages.removeLast());
          }
          return;
        case 'add_message':
          final args = call.arguments as Map;
          final text = args['text'] as String? ?? '';
          final isUser = args['isUser'] as bool? ?? false;
          if (text.isNotEmpty) {
            setState(() {
              _messages.add(_ChatMessage(text: text, isUser: isUser));
              _isLoading = isUser;
            });
            _scrollToBottom();
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
    await windowManager.setMinimumSize(Size(w, h));
    await windowManager.setMaximumSize(Size(w, h));
    await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
    if (args['hidden'] != true) {
      await windowManager.show();
    }
    if (mounted) setState(() { _theme = AgentChatColors.of(theme); _themeName = theme; });
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

  @override
  Widget build(BuildContext context) {
    final isDark = _themeName == 'dark';
    return MouseRegion(
      onEnter: (_) =>
          AgentChatPopup.popupChannel.invokeMethod('agent_chat_popup_enter'),
      onExit: (_) =>
          AgentChatPopup.popupChannel.invokeMethod('agent_chat_popup_exit'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: isDark ? Brightness.dark : Brightness.light,
          fontFamily: 'NotoSansSC',
        ),
        home: Scaffold(
          backgroundColor: _theme.scaffoldBg,
          body: Container(
            padding: const EdgeInsets.all(12),
            color: _theme.scaffoldBg,
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                Expanded(child: _buildChatList()),
                _buildThemeToggleRow(),
                _buildStatusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
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
      ],
    );
  }

  Widget _buildThemeToggleRow() {
    final isDark = _themeName == 'dark';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          GestureDetector(
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _theme.chipActiveBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    size: 13,
                    color: _theme.statusText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isDark ? '明亮' : '暗黑',
                    style: TextStyle(color: _theme.statusText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final chars = _messages.fold<int>(0, (sum, m) => sum + m.text.length);
    final sizeStr = chars >= 1024
        ? '${(chars / 1024).toStringAsFixed(chars >= 10240 ? 0 : 1)}k'
        : '${chars}b';
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'context: $sizeStr',
          style: TextStyle(color: _theme.statusText, fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty && !_isLoading) {
      return Center(
        child: Text(
          '暂无消息',
          style: TextStyle(color: _theme.emptyText, fontSize: 13),
        ),
      );
    }
    return Theme(
      data: ThemeData(
        brightness: _themeName == 'dark' ? Brightness.dark : Brightness.light,
        scrollbarTheme: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(0),
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _messages.length + (_isLoading ? 1 : 0),
        itemBuilder: (_, index) {
          if (_isLoading && index == _messages.length) {
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
            data: msg.text,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: _theme.bubbleText, fontSize: 13),
              h1: TextStyle(color: _theme.bubbleText, fontSize: 18, fontWeight: FontWeight.bold),
              h2: TextStyle(color: _theme.bubbleText, fontSize: 16, fontWeight: FontWeight.bold),
              h3: TextStyle(color: _theme.bubbleText, fontSize: 15, fontWeight: FontWeight.bold),
              h4: TextStyle(color: _theme.bubbleText, fontSize: 14, fontWeight: FontWeight.w600),
              h5: TextStyle(color: _theme.bubbleText, fontSize: 13, fontWeight: FontWeight.w600),
              h6: TextStyle(color: _theme.bubbleText, fontSize: 13, fontWeight: FontWeight.w600),
              code: TextStyle(
                color: _theme.bubbleText,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              codeblockDecoration: BoxDecoration(
                color: _theme.bubbleText.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              a: TextStyle(color: _theme.bubbleText),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildActionButton('assets/svg/复制.svg', '复制', () {
                Clipboard.setData(ClipboardData(text: msg.text));
              }),
              const SizedBox(width: 8),
              _buildActionButton('assets/svg/重新.svg', '重新生成', () {
                AgentChatPopup.popupChannel
                    .invokeMethod('agent_regenerate');
              }),
              const SizedBox(width: 8),
              _buildActionButton('assets/svg/more.svg', '更多', () {
                // TODO: 更多操作
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String svgAsset, String label, VoidCallback onTap) {
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
  _ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}
