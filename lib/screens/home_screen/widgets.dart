part of 'home_screen.dart';

extension _HomeScreenWidgets on _HomeScreenState {
  Widget _buildChatBody() {
    final isEmpty = _messages.isEmpty && !_isSending;
    final theme = _themeData;
    return Container(
      color: theme.surface,
      child: Column(
        children: [
          if (_showSessionTabs) _buildSessionTabs(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: isEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: _buildAgentHints(),
                        ),
                      ],
                    )
                  : _buildChatList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: _buildInputArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentHints() => Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 430),
          child: _AgentHints(),
        ),
      );
}

class _AgentHints extends StatefulWidget {
  const _AgentHints();

  @override
  State<_AgentHints> createState() => _AgentHintsState();
}

class _AgentHintsState extends State<_AgentHints> {
  int? _hoveredIndex;

  static const _hints = [
    ('assets/png/agentHint/1.png', '描述一个目标，让 Orbby 帮你拆解并完成它'),
    ('assets/png/agentHint/2.svg', '让 Orbby 阅读文件、整理资料或分析复杂问题'),
    ('assets/png/agentHint/3.svg', '输入 / 查看命令，快速唤起更多工作方式'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Text(
            'Orbby，让想法成为现实',
            textAlign: TextAlign.left,
            style: TextStyle(
              color: theme.ink,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              fontFamily: _fontFamily,
            ),
          ),
        ),
        for (var i = 0; i < _hints.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 16),
            child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredIndex = i),
            onExit: (_) {
              if (_hoveredIndex == i) {
                setState(() => _hoveredIndex = null);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
              decoration: BoxDecoration(
                color: _hoveredIndex == i
                    ? theme.line.withValues(alpha: 0.35)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: _hints[i].$1.endsWith('.svg')
                        ? SvgPicture.asset(_hints[i].$1)
                        : Image.asset(_hints[i].$1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_hints[i].$2, textAlign: TextAlign.left, style: TextStyle(color: theme.ink2, fontSize: 13))),
                ],
              ),
            ),
            ),
          ),
      ],
    );
  }
}
