part of 'home_screen.dart';

/// 顶部会话 tab 栏：多会话切换、关闭（新建会话走 /new 命令或「＋」按钮）。
/// 纯展示与交互；tab 状态（标题/运行中/待回答标记）读各会话的 ChatSessionView。
/// 切换不检查 isSending——A 会话跑着切到 B 继续干活是多会话的核心用法。
///
/// 会话 tab 数量上限：tab 宽 = 栏宽 1/4，4 个恰好占满一行，超过须先关闭
const _maxSessionTabs = 4;

/// 视觉（参考稿「浮动胶囊」）：栏高 50、surface 底 + 底部 hairline；
/// 激活 tab = raised 底 + line 描边 + 微影（浮起），非激活透明融入栏底、
/// hover 浅底；右端「＋」新建与主题切换按钮。
extension _HomeScreenTabs on _HomeScreenState {
  Widget _buildSessionTabs() {
    final theme = _themeData;
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.lineSoft)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // tab 宽 = 栏宽 1/4（4 个恰好占满一行，超出横向滚动）。
          // tab 在横向滚动区内宽度约束无限，须在此层取栏宽算好传入；
          // 栏宽极窄时兜底 90，防状态点/文字/关闭按钮被挤没
          final tabWidth =
              (constraints.maxWidth / 4).clamp(90.0, double.infinity).toDouble();
          return SizedBox(
            height: 50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < _views.length; i++)
                            _buildSessionTab(_views[i], i, tabWidth),
                        ],
                      ),
                    ),
                  ),
                  _buildTabAddButton(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionTab(ChatSessionView view, int index, double width) {
    final theme = _themeData;
    final active = index == _activeIndex;
    final title = view.conversation?.title.trim().isNotEmpty == true
        ? view.conversation!.title
        : '新会话';
    return _HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: () => _switchSession(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          width: width,
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.only(left: 10, right: 5),
          decoration: BoxDecoration(
            // 激活 = 浮起的 raised 胶囊 + 描边 + 微影；非激活透明，hover 浅底
            color: active
                ? theme.raised
                : (hovered ? theme.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? theme.line : Colors.transparent,
            ),
            boxShadow: active ? theme.cardShadows : null,
          ),
          child: Row(
            children: [
              // 运行中：橙点闪烁；挂起提问未答：红点常亮（后台会话提问
              // 卡片不可见，靠这里提醒用户切过去回答）
              if (view.isSending)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _toolBlinkOn ? theme.run : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                )
              else if (view.questionCtrl != null)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: theme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? theme.ink : theme.ink2,
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.1,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // 关闭按钮：hover 到本体时红底白叉（终端/浏览器标准关闭暗示）；
              // 平时弱化，tab 整体 hover 或激活时才清晰
              _buildTabCloseButton(index, active || hovered),
            ],
          ),
        ),
      ),
    );
  }

  /// tab 关闭按钮（内嵌独立 hover 跟踪，与 tab 本体的 hover 互不干扰）
  Widget _buildTabCloseButton(int index, bool emphasized) {
    final theme = _themeData;
    return _HoverBuilder(
      builder: (hovered) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _closeSessionTab(index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: hovered ? theme.danger : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close,
              size: 12,
              color: hovered
                  ? Colors.white
                  : (emphasized ? theme.ink2 : theme.ink3),
            ),
          ),
        ),
      ),
    );
  }

  /// 「＋」新建会话 tab：把 /new 命令显式化（参考稿新增项）
  Widget _buildTabAddButton() {
    final theme = _themeData;
    return _HoverBuilder(
      builder: (hovered) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _openNewSessionTab,
          behavior: HitTestBehavior.opaque,
          child: Tooltip(
            message: '新建会话（/new）',
            waitDuration: const Duration(milliseconds: 500),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: hovered ? theme.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.add, size: 16, color: theme.ink3),
            ),
          ),
        ),
      ),
    );
  }

  /// 切换会话 tab：草稿与滚动位置随会话存回/恢复，消息列表经 `_current`
  /// 转发整体换源。不检查 isSending——后台会话继续流式跑，回来时内容已就绪。
  void _switchSession(int index) {
    if (index == _activeIndex || index < 0 || index >= _views.length) return;
    _saveScrollState();
    setState(() {
      _current.inputDraft = _inputController.text;
      _activeIndex = index;
      _setInputText(_current.inputDraft);
    });
    _restoreScrollState();
    _loadWorkspaceLabel();
    _focusInput();
  }

  /// 保存当前会话的滚动状态到它的 view（切换/新建 tab 换源前调用）。
  /// 必须在换源 setState 之前：controller 的 pixels 还是旧列表的位置
  void _saveScrollState() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _current.scrollOffset = position.pixels;
    _current.atBottom =
        position.pixels >= position.maxScrollExtent - 50;
  }

  /// 恢复当前会话的滚动状态（换源的下一帧列表已布局完再跳）。
  /// 贴底/无记录 → 跳到底部（后台流式增长后仍跟随最新）；否则跳回离开
  /// 时的位置（会话内容变短时 clamp 到底部）。瞬时 jumpTo，无动画
  void _restoreScrollState() {
    final view = _current;
    _showScrollToBottom = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(view, _current)) return;
      if (!_scrollController.hasClients) {
        _onChatScroll();
        return;
      }
      final position = _scrollController.position;
      final target = (view.atBottom || view.scrollOffset == null)
          ? position.maxScrollExtent
          : view.scrollOffset!.clamp(0.0, position.maxScrollExtent);
      _scrollController.jumpTo(target);
      // jumpTo 未改变 pixels 时 scroll listener 不触发，手动刷新回底按钮显隐
      _onChatScroll();
    });
  }

  /// 新建会话 tab（/new 命令入口）：旧会话原地保留继续可切回。
  /// 上限 [_maxSessionTabs]，达到后提示先关闭再新建
  void _openNewSessionTab() {
    if (_views.length >= _maxSessionTabs) {
      _addLocalMessage('会话 tab 已达上限（$_maxSessionTabs 个），关闭一个后再新建。');
      return;
    }
    _saveScrollState();
    final view = ChatSessionView(agentSessionId: AgentService.newSessionId());
    setState(() {
      _current.inputDraft = _inputController.text;
      _views.add(view);
      _activeIndex = _views.length - 1;
      _inputController.clear();
    });
    _restoreScrollState();
    _focusInput();
  }

  /// 关闭会话 tab：运行中的请求先取消（流式收尾写的是已移除的 view，无 UI 副作用），
  /// Node 侧内存会话同步回收（防孤儿累积），会话内容最后落盘一次。
  /// 最后一个 tab 关闭后自动补一个空 tab，保证 `_views` 恒非空。
  void _closeSessionTab(int index) {
    if (index < 0 || index >= _views.length) return;
    final view = _views[index];
    if (view.isSending) AgentService.cancelCurrent(sessionId: view.agentSessionId);
    // 回收 Node 内存上下文；reset 是幂等的（会话不存在时惰性语义下无副作用）
    AgentService.resetConversation(sessionId: view.agentSessionId);
    _saveConversation(view);
    // dispose 后必须置 null：取消触发的流式收尾还会走 _dismissQuestionCard(view)，
    // 二次 dispose ChangeNotifier 会炸 debug 断言
    view.questionCtrl?.dispose();
    view.questionCtrl = null;
    view.questionId = null;
    view.attachmentCtrl.dispose();
    final previous = _current;
    setState(() {
      _views.removeAt(index);
      if (_views.isEmpty) {
        _views.add(ChatSessionView(agentSessionId: AgentService.newSessionId()));
        _activeIndex = 0;
        _inputController.clear();
      } else if (_activeIndex > index) {
        _activeIndex--;
      } else if (_activeIndex == index) {
        // 关的是当前 tab：激活位停在原地（即下一个），恢复那个会话的草稿
        if (_activeIndex >= _views.length) _activeIndex = _views.length - 1;
        _setInputText(_current.inputDraft);
      }
    });
    // 只有前台会话变了（关的是当前 tab / 全关补空 tab）才恢复其滚动位置；
    // 关后台 tab 时前台视图不得被拽动
    if (!identical(previous, _current)) _restoreScrollState();
  }
}

/// tab 行的 hover 态跟踪（关闭按钮显隐用）；builder 模式避免为 tab 单独建 State
class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder});
  final Widget Function(bool hovered) builder;
  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}
