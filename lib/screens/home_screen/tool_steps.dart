part of 'home_screen.dart';

/// 工具步骤折叠组：同一条消息气泡内的 ≥2 个工具调用默认全部折叠，
/// 只显示概览头（运行状态 + 项数 + 去重操作名），展开后显示全部行（整体缩进）。
/// 折叠状态由宿主持有（_ChatMessage.toolsExpanded，瞬态不落盘，重载会话后默认折叠）。
/// 行渲染复用 messages.dart 的 [_HomeScreenMessages._buildToolRow]。
class _ToolStepsGroup extends StatelessWidget {
  const _ToolStepsGroup({
    required this.events,
    required this.expanded,
    required this.blinkOn,
    required this.onToggle,
    required this.rowBuilder,
    required this.theme,
  });

  final List<_ToolEvent> events;
  final bool expanded;
  final bool blinkOn;
  final VoidCallback onToggle;

  /// 当前主题 token（宿主传入，避免依赖 build context）
  final ChatThemeData theme;

  /// 行渲染交回宿主（_buildToolRow），组件不复制行 UI
  final Widget Function(_ToolEvent event) rowBuilder;

  bool get _anyRunning => events.any((e) => e.running);
  int get _errorCount => events.where((e) => e.error).length;

  /// 概览文案：正在执行 5 项操作：读取文件、执行 PowerShell。
  /// 同名操作去重只显示一次（LinkedHashSet 保序），全部列出，超长由 ellipsis 截断。
  String get _summary {
    final names = <String>{};
    for (final event in events) {
      names.add(toolDisplayName(event.name));
    }
    return '${_anyRunning ? '正在执行' : '已执行'} ${events.length} 项操作：${names.join('、')}';
  }

  @override
  Widget build(BuildContext context) {
    final allError = _errorCount == events.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 概览头：禁用文字选择（SelectionArea 会吞掉落在文字上的点击），保证整行可点
        SelectionContainer.disabled(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                // 正文左缩进 24（参考稿 .tool-head），工具行再退到 38
                padding: const EdgeInsets.fromLTRB(24, 7, 12, 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 状态圆点 7px：运行中橙色闪烁；全部失败红色；其余信息蓝
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: AnimatedOpacity(
                        opacity: _anyRunning && !allError ? (blinkOn ? 1.0 : 0.2) : 1.0,
                        duration: const Duration(milliseconds: 180),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: allError
                                ? theme.danger
                                : (_anyRunning ? theme.run : theme.info),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    // 展开箭头：旋转指示展开/收起
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.chevron_right, size: 14, color: theme.ink3),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: _buildSummaryText()),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 展开时全部行整体缩进（相对概览头），保留组层级感；折叠时不渲染任何行
        if (expanded)
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: rowBuilder(event),
            ),
      ],
    );
  }

  Widget _buildSummaryText() {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: _summary),
          if (_errorCount > 0)
            TextSpan(
              text: ' · $_errorCount 个失败',
              style: TextStyle(color: theme.danger),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.ink2,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        fontFamily: _fontFamily,
      ),
    );
  }
}
