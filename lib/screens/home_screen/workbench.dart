part of 'home_screen.dart';

/// 欢迎页工作台（空态分支的内容列，替换原 _AgentHints 品牌区）。
/// 参考 plan/component/workbench-preview.html：时间问候 + 快捷入口任务卡 +
/// 技能橱窗 + 项目/工作区续接，全部映射既有主题 token（无新增色值）。
///
/// 数据源：技能 = _skillPalette（skills.changed 推送热更新即时反映）；
/// 工作区续接 = WorkspaceHistoryService 的 /cd MRU 历史（独立文件持久化、
/// 与会话无关），宿主截取前 [_workbenchMaxWorkspaces] 条传入。
///
/// 点击行为（设计稿约定）：任务卡 / 技能 chip 只**填入输入框并聚焦、
/// 不自动发送**——填「/help」「@」这类片段由 _onInputChanged 自动唤起
/// 对应面板；技能引用尾随空格 = 面板确认语义，不弹面板。续接行点击 =
/// 切回该工作区（_resumeWorkspace，/cd 语义）。

/// 技能橱窗最多直接展示的 chip 数，超出折叠为「＋N」
/// （点击填「@」唤起完整技能面板）
const _workbenchMaxSkillChips = 4;

/// 「项目 / 工作区」续接最多展示的条数（存储上限见 WorkspaceHistoryService）
const _workbenchMaxWorkspaces = 5;

/// 时间问候副标题（固定品牌句）
const _workbenchGreetingSub = '让想法成为现实 —— 从一句话开始';

/// 任务卡：静态配置三条（设计说明 01），点击填 [fill] 进输入框
const _workbenchTasks = [
  _WorkbenchTask(
    icon: 'assets/png/workbench_todo.png',
    title: '待办事项',
    subtitle: '查看当前待办与进度',
    fill: '查看当前待办与进度',
  ),
  _WorkbenchTask(
    icon: 'assets/svg/workbench_resume.svg',
    title: '继续任务',
    subtitle: '从最近的对话中选择并继续',
    fill: '从最近的对话中选择并继续',
  ),
  _WorkbenchTask(
    icon: 'assets/svg/workbench_help.svg',
    title: '使用说明',
    subtitle: '了解常用命令与功能',
    fill: 'usage-guide',
  ),
];

/// 按本地时间取五档问候主标题（设计说明 03 的档位表）
String _workbenchGreetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 23 || hour < 5) return '夜深了。安静的时刻适合想清楚事情。';
  if (hour >= 18) return '晚上好。想捣鼓点什么？';
  if (hour >= 14) return '下午好。继续推进手头的事。';
  if (hour >= 11) return '中午好。趁间隙理清一件事。';
  return '早上好。今天从哪件事开始？';
}

/// 任务卡条目（静态配置，见 [_workbenchTasks]）
class _WorkbenchTask {
  const _WorkbenchTask({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.fill,
  });

  /// asset 路径（.svg 走 SvgPicture，其余 Image.asset，同旧 _AgentHints）
  final String icon;
  final String title;
  final String subtitle;

  /// 点击填入输入框的文本（不自动发送）
  final String fill;
}

/// 工作台主体：纯展示组件，数据全部由宿主传入；hover 状态自管。
/// 空即藏：[skills] / [workspaces] 为空时对应整节收起（首跑态只剩
/// 问候 + 任务卡）。
class _Workbench extends StatefulWidget {
  const _Workbench({
    required this.skills,
    required this.workspaces,
    required this.commands,
    required this.onShowUsageGuide,
    required this.onFillInput,
    this.onManageSkills,
    this.onResumeWorkspace,
  });

  final List<ChatSkill> skills;

  /// /cd 工作区 MRU 历史（WorkspaceHistoryService，路径字符串列表）
  final List<String> workspaces;
  final List<ChatCommand> commands;
  final VoidCallback onShowUsageGuide;

  /// 填入输入框并聚焦（任务卡 / 技能 chip / ＋N 共用）
  final void Function(String text) onFillInput;

  /// 「管理 →」（技能节头）；null 时按钮不渲染
  final VoidCallback? onManageSkills;

  /// 续接行点击（切回该工作区）；null 时行不可点击
  final void Function(String path)? onResumeWorkspace;

  @override
  State<_Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<_Workbench> {
  /// 问候主标题：本地时间取档，menu 窗口每次被唤出（menuWindowShown）
  /// 时刷新——隐藏期间跨过档位边界，下次唤出即更新
  late String _greeting = _workbenchGreetingFor(DateTime.now());

  @override
  void initState() {
    super.initState();
    menuWindowShown.addListener(_refreshGreeting);
  }

  @override
  void dispose() {
    menuWindowShown.removeListener(_refreshGreeting);
    super.dispose();
  }

  void _refreshGreeting() {
    final greeting = _workbenchGreetingFor(DateTime.now());
    if (greeting != _greeting) setState(() => _greeting = greeting);
  }

  void _openTask(_WorkbenchTask task) {
    if (task.fill == 'usage-guide') {
      widget.onShowUsageGuide();
    } else {
      widget.onFillInput(task.fill);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 时间问候 ──
        Text(
          _greeting,
          style: TextStyle(
            color: theme.ink,
            fontSize: 24,
            height: 1.5,
            letterSpacing: -0.6,
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _workbenchGreetingSub,
          style: TextStyle(
            color: theme.ink3,
            fontSize: 13,
            height: 1.8,
            fontFamily: _fontFamily,
          ),
        ),
        const SizedBox(height: 26),
        _buildSection(
          label: '快捷入口',
          child: _buildTaskCards(),
        ),
        // 空即藏：无技能整节收起
        if (widget.skills.isNotEmpty) ...[
          const SizedBox(height: 26),
          _buildSection(
            label: '技能',
            more: widget.onManageSkills == null
                ? null
                : _buildSectionMore('管理 →', widget.onManageSkills!),
            child: _buildSkillChips(),
          ),
        ],
        // 空即藏：无 /cd 历史整节收起（首跑态）
        if (widget.workspaces.isNotEmpty) ...[
          const SizedBox(height: 26),
          _buildSection(
            label: '项目 / 工作区',
            child: _buildResumeList(),
          ),
        ],
      ],
    );
  }

  /// 节头：小字标签 + hairline 分隔线 + 可选动作按钮（设计稿 .sec-head）
  Widget _buildSection({required String label, Widget? more, required Widget child}) {
    final theme = ChatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: theme.ink3,
                fontSize: 11,
                letterSpacing: 2.5,
                fontFamily: _fontFamily,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 1, color: theme.lineSoft)),
            if (more != null) ...[const SizedBox(width: 12), more],
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  /// 节头动作按钮（「管理 →」）
  Widget _buildSectionMore(String label, VoidCallback onTap) {
    return _HoverBox(
      builder: (context, hovered) {
        final theme = ChatTheme.of(context);
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Text(
            label,
            style: TextStyle(
              color: hovered ? theme.ink2 : theme.ink3,
              fontSize: 11,
              letterSpacing: 1,
              fontFamily: _fontFamily,
            ),
          ),
        );
      },
    );
  }

  /// 任务卡：3 列起步，窄窗降 2/1 列（设计说明 02；menu 窗宽 = 屏宽 1/3）
  Widget _buildTaskCards() {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 460 ? 3 : (width >= 300 ? 2 : 1);
      final rows = <Widget>[];
      for (var i = 0; i < _workbenchTasks.length; i += columns) {
        final chunk = _workbenchTasks.skip(i).take(columns).toList();
        if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
        // IntrinsicHeight + stretch：同行卡片等高（grid 默认 stretch 语义）；
        // 直接 Row.stretch 在 Column(min) 的无界高度下会布局崩溃
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < chunk.length; j++) ...[
                  if (j > 0) const SizedBox(width: 10),
                  Expanded(child: _buildTaskCard(chunk[j])),
                ],
              ],
            ),
          ),
        );
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    });
  }

  Widget _buildTaskCard(_WorkbenchTask task) {
    return _HoverBox(
      builder: (context, hovered) {
        final theme = ChatTheme.of(context);
        return GestureDetector(
          onTap: () => _openTask(task),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            decoration: BoxDecoration(
              color: theme.raised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hovered ? theme.accentDeep : theme.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: task.icon.endsWith('.svg')
                      ? SvgPicture.asset(task.icon)
                      : Image.asset(task.icon),
                ),
                const SizedBox(height: 10),
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.ink,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    fontFamily: _fontFamily,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.ink3,
                    fontSize: 12,
                    height: 1.6,
                    fontFamily: _fontFamily,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 技能橱窗：前 [_workbenchMaxSkillChips] 个直出 chip，超出折叠「＋N」
  /// （点击填「@」唤起完整技能面板）；「＋N」沿用 chip 样式的弱化形态
  Widget _buildSkillChips() {
    final visible = widget.skills.take(_workbenchMaxSkillChips).toList();
    final overflow = widget.skills.length - visible.length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final skill in visible)
          _buildSkillChip(
            '@${skill.name} ',
            highlight: true,
            onTap: () => widget.onFillInput('@${skill.name} '),
          ),
        if (overflow > 0)
          _buildSkillChip(
            '＋$overflow',
            onTap: () => widget.onFillInput('@'),
          ),
      ],
    );
  }

  Widget _buildSkillChip(String label, {bool highlight = false, required VoidCallback onTap}) {
    return _HoverBox(
      builder: (context, hovered) {
        final theme = ChatTheme.of(context);
        // 弱化形态（＋N）：ink3 文字；常规 chip：'@' 前缀琥珀强调 + 技能名
        final fg = highlight
            ? (hovered ? theme.ink : theme.ink2)
            : (hovered ? theme.ink2 : theme.ink3);
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: hovered ? theme.hover : theme.raised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.line),
            ),
            child: highlight
                ? Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '@',
                        style: TextStyle(
                          color: theme.accentDeep,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: label.substring(1)),
                    ]),
                    style: TextStyle(
                      color: fg,
                      fontSize: 12,
                      fontFamily: _fontFamily,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 12,
                      fontFamily: _fontFamily,
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// 项目 / 工作区续接行：目录图标 + 路径（等宽、单行省略）+ 箭头
  Widget _buildResumeList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.workspaces.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _buildResumeRow(widget.workspaces[i]),
        ],
      ],
    );
  }

  Widget _buildResumeRow(String path) {
    return _HoverBox(
      builder: (context, hovered) {
        final theme = ChatTheme.of(context);
        final onTap = widget.onResumeWorkspace == null
            ? null
            : () => widget.onResumeWorkspace!(path);
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: hovered ? theme.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 19, color: theme.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hovered ? theme.ink : theme.ink2,
                      fontSize: 12.5,
                      fontFamily: _codeFont,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.east, size: 15, color: hovered ? theme.ink2 : theme.ink3),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 轻量 hover 容器（builder 收 hovered 布尔）：卡片 / chip / 行共用，
/// hover 态各自隔离在子树内，不撑大宿主 State。
class _HoverBox extends StatefulWidget {
  const _HoverBox({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<_HoverBox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}
