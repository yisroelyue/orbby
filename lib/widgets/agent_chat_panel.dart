import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import 'typing_indicator.dart';

/// Shared color constants for agent chat (panel + popup).
class AgentChatColors {
  const AgentChatColors._();

  static const light = AgentChatPalette(
    bg: Color(0xFFFFFFFF),
    inputBg: Color(0x0D000000),
    inputText: Color(0xFF333333),
    inputHint: Color(0xFF000000),
    chipActiveBg: Color(0x14000000),
    chipActiveText: Color(0xFF333333),
    chipInactiveText: Color(0xFF999999),
    headerText: Color(0xFF333333),
    userBubble: Color(0xFFE0E0E0),
    agentBubble: Color(0xFFD5D5D5),
    bubbleText: Color(0xFF333333),
    emptyText: Color(0xFF999999),
    statusText: Color(0xFF000000),
    scaffoldBg: Color(0xFFFFFFFF),
    dividerColor: Color(0xFFE0E0E0),
  );

  static const dark = AgentChatPalette(
    bg: Color(0xFF1E1E1E),
    inputBg: Color(0xFF2A2A2A),
    inputText: Color(0xB3FFFFFF),
    inputHint: Color(0x4DFFFFFF),
    chipActiveBg: Color(0x26FFFFFF),
    chipActiveText: Color(0xB3FFFFFF),
    chipInactiveText: Color(0x4DFFFFFF),
    headerText: Colors.white,
    userBubble: Color(0xFF3A3A3A),
    agentBubble: Color(0xFF2A2A2A),
    bubbleText: Colors.white,
    emptyText: Color(0x4DFFFFFF),
    statusText: Color(0xFFFFFFFF),
    scaffoldBg: Color(0xFF1E1E1E),
    dividerColor: Color(0xFF3A3A3A),
  );

  static AgentChatPalette of(String theme) => theme == 'dark' ? dark : light;
}

class AgentChatPalette {
  const AgentChatPalette({
    required this.bg,
    required this.inputBg,
    required this.inputText,
    required this.inputHint,
    required this.chipActiveBg,
    required this.chipActiveText,
    required this.chipInactiveText,
    required this.headerText,
    required this.userBubble,
    required this.agentBubble,
    required this.bubbleText,
    required this.emptyText,
    required this.statusText,
    required this.scaffoldBg,
    required this.dividerColor,
  });

  final Color bg;
  final Color inputBg;
  final Color inputText;
  final Color inputHint;
  final Color chipActiveBg;
  final Color chipActiveText;
  final Color chipInactiveText;
  final Color headerText;
  final Color userBubble;
  final Color agentBubble;
  final Color bubbleText;
  final Color emptyText;
  final Color statusText;
  final Color scaffoldBg;
  final Color dividerColor;
}

class AgentChatPanel extends StatefulWidget {
  const AgentChatPanel({super.key});

  static final chatLoadingNotifier = ValueNotifier<bool>(false);

  @override
  State<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends State<AgentChatPanel> {
  final _controller = TextEditingController();
  String _mode = 'accept';
  AgentChatPalette _theme = AgentChatColors.light;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    MenuScreen.refreshNotifier.addListener(_loadTheme);
    AgentChatPanel.chatLoadingNotifier.addListener(_onLoadingChanged);
  }

  @override
  void dispose() {
    MenuScreen.refreshNotifier.removeListener(_loadTheme);
    AgentChatPanel.chatLoadingNotifier.removeListener(_onLoadingChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onLoadingChanged() {
    if (mounted) setState(() => _isSending = AgentChatPanel.chatLoadingNotifier.value);
  }

  Future<void> _loadTheme() async {
    final s = await SettingsService.load();
    if (!mounted) return;
    setState(() => _theme = AgentChatColors.of(s.appTheme));
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    AgentChatPanel.chatLoadingNotifier.value = true;
    MenuScreen.menuChannel.invokeMethod('agent_send_message', {
      'text': text,
      'mode': _mode,
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => MenuScreen.menuChannel.invokeMethod('agent_chat_enter'),
      onExit: (_) => MenuScreen.menuChannel.invokeMethod('agent_chat_exit'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _theme.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInputArea(),
              const SizedBox(height: 10),
              _buildModeBar(),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildInputArea() {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: 5,
        enabled: !_isSending,
        style: TextStyle(color: _theme.inputText, fontSize: 13),
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
          prefixIcon: _isSending
              ? const Padding(
                  padding: EdgeInsets.only(left: 12, right: 4),
                  child: TypingIndicator(),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildModeBar() {
    return Row(
      children: [
        _buildModeChip('accept'),
        const SizedBox(width: 6),
        _buildModeChip('plan'),
        const SizedBox(width: 6),
        _buildModeChip('auto'),
      ],
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
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
