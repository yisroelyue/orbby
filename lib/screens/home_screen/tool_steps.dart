part of 'home_screen.dart';

/// 工具步骤折叠组：同一条消息气泡内的 ≥2 个工具调用默认全部折叠，
/// 只显示概览头（运行状态 + 项数 + 去重操作名），展开后显示全部行（整体缩进）。
/// 折叠状态由宿主持有（_ChatMessage.toolsExpanded，瞬态不落盘，重载会话后默认折叠）。
/// 行渲染复用 messages.dart 的 [_HomeScreenMessages._buildToolRow]。
class _ToolStepsGroup extends StatelessWidget {
  const _ToolStepsGroup({
    required this.events,
    required this.expanded,
    required this.onToggle,
    required this.rowBuilder,
    required this.theme,
  });

  final List<_ToolEvent> events;
  final bool expanded;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 概览头：整行可点展开/收起
        MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                // 概览头与正文左对齐（无缩进），展开行再退一档保留组层级
                padding: const EdgeInsets.fromLTRB(0, 12, 12, 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 用竖线作为操作摘要的层级标记
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: theme.ink3.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                        child: _buildSummaryText(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ),
        // 展开时全部行整体缩进一档（相对概览头/正文），保留组层级感；折叠时不渲染任何行
        if (expanded)
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(left: 6),
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
      // 概览行是辅助信息：比工具行标题小一档、降 ink3、不加粗（参考稿 .tool-row）
      style: TextStyle(
        color: theme.ink3,
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        fontFamily: _fontFamily,
      ),
    );
  }
}
