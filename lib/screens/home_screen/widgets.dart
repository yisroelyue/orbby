part of 'home_screen.dart';

/// 页面展示骨架：聊天主体容器、欢迎页、建议入口图标、聊天区域编排。
extension _HomeScreenWidgets on _HomeScreenState {
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
}
