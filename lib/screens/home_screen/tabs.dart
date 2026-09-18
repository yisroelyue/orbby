part of 'home_screen.dart';

/// 顶部会话 tab 栏：多会话切换、关闭（新建会话走 /new 命令）。
/// 纯展示与交互；tab 状态（标题/运行中/待回答标记）读各会话的 ChatSessionView。
/// 切换不检查 isSending——A 会话跑着切到 B 继续干活是多会话的核心用法。
///
/// 会话 tab 数量上限：tab 宽 = 栏宽 1/4，4 个恰好占满一行，超过须先关闭
const _maxSessionTabs = 4;

/// 视觉（Windows Terminal 式"从页面凸出的一块"）：栏底 _panelBg，tab 宽 = 栏宽 1/4；
/// 激活 tab 用内容区同色 _scaffoldBg 且底边与内容区平齐，读起来就是内容区
/// 向上凸出的一块；非激活 tab 透明融入栏底，hover 轻微提亮。无描边无阴影。
extension _HomeScreenTabs on _HomeScreenState {
  Widget _buildSessionTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: _panelBg,
        // 与外层聊天容器同款 top 圆角，贴满容器顶部不溢出
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // tab 宽 = 栏宽 1/4（4 个恰好占满一行，超出横向滚动）。
          // tab 在横向滚动区内宽度约束无限，须在此层取栏宽算好传入；
          // 栏宽极窄时兜底 90，防状态点/文字/关闭按钮被挤没
          final tabWidth =
              (constraints.maxWidth / 4).clamp(90.0, double.infinity).toDouble();
          return SizedBox(
            height: 34,
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
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionTab(ChatSessionView view, int index, double width) {
    final active = index == _activeIndex;
    final title = view.conversation?.title.trim().isNotEmpty == true
        ? view.conversation!.title
        : '新会话';
    return _HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: () => _switchSession(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: double.infinity,
          width: width,
          margin: const EdgeInsets.only(right: 2),
          // 左右内边距：右侧关闭按钮自带占位（4→8 抬一点），左侧与视觉留白对齐
          padding: const EdgeInsets.only(left: 14, right: 8),
          decoration: BoxDecoration(
            // 激活 = 内容区同色（底边与栏底平齐，向下无缝衔接），像内容区
            // 向上凸出的一块；非激活透明融入栏底，hover 轻微提亮
            color: active
                ? _scaffoldBg
                : (hovered ? _tabHoverBg : Colors.transparent),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              // 运行中：橙色圆点闪烁；挂起提问未答：红点常亮（后台会话提问
              // 卡片不可见，靠这里提醒用户切过去回答）
              if (view.isSending)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _toolBlinkOn ? Colors.orangeAccent : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                )
              else if (view.questionCtrl != null)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? _statusText : _bubbleText,
                    fontSize: 12,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // 关闭按钮：hover 到本体时红底白叉（终端/浏览器标准关闭暗示）；
              // 平时半透明弱化，tab 整体 hover 或激活时才清晰
              _buildTabCloseButton(index, active || hovered),
            ],
          ),
        ),
      ),
    );
  }

  /// tab 关闭按钮（内嵌独立 hover 跟踪，与 tab 本体的 hover 互不干扰）
  Widget _buildTabCloseButton(int index, bool emphasized) {
    return _HoverBuilder(
      builder: (hovered) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _closeSessionTab(index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: hovered ? Colors.redAccent : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close,
              size: 12,
              color: hovered
                  ? Colors.white
                  : (emphasized ? _bubbleText : _bubbleText.withValues(alpha: 0.35)),
            ),
          ),
        ),
      ),
    );
  }

  /// 切换会话 tab：草稿随会话存回/恢复，消息列表经 `_current` 转发整体换源。
  /// 不检查 isSending——后台会话继续流式跑，回来时内容已就绪。
  void _switchSession(int index) {
    if (index == _activeIndex || index < 0 || index >= _views.length) return;
    setState(() {
      _current.inputDraft = _inputController.text;
      _activeIndex = index;
      _setInputText(_current.inputDraft);
    });
    _scrollToBottom(force: true);
    _focusInput();
  }

  /// 新建会话 tab（/new 命令入口）：旧会话原地保留继续可切回。
  /// 上限 [_maxSessionTabs]，达到后提示先关闭再新建
  void _openNewSessionTab() {
    if (_views.length >= _maxSessionTabs) {
      _addLocalMessage('会话 tab 已达上限（$_maxSessionTabs 个），关闭一个后再新建。');
      return;
    }
    final view = ChatSessionView(agentSessionId: AgentService.newSessionId());
    setState(() {
      _current.inputDraft = _inputController.text;
      _views.add(view);
      _activeIndex = _views.length - 1;
      _inputController.clear();
    });
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
    _scrollToBottom(force: true);
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
