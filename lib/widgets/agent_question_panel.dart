import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_question.dart';
import '../theme/chat_theme.dart';

/// Agent 提问卡片的三层结构（与 CommandPalette 同构）：
/// [AgentQuestionPanelController] 纯逻辑（状态/键盘导航/答案组装），
/// [AgentQuestionPanel] 纯展示（只读 controller + onSubmit/onSkip 回调），
/// 宿主（HomeScreen）持有 controller、接管键盘、负责发送答案与留痕。
///
/// 交互定案：
/// - 单问题单选 choice：点击选项行 / Enter = 直接提交（最高频路径，零额外操作）。
/// - 其余（多选 / text / 多问题）：先选择或输入，经底部"提交"按钮或 Enter 提交。
/// - Esc / "跳过" = 全部空答案（LLM 侧视为未回答）。

class AgentQuestionPanelController extends ChangeNotifier {
  AgentQuestionPanelController({required this.questions}) {
    for (final _ in questions) {
      _selections.add(<int>{});
      _textCtrls.add(TextEditingController());
    }
  }

  final List<AgentQuestion> questions;

  final List<Set<int>> _selections = [];
  final List<TextEditingController> _textCtrls = [];

  /// 键盘导航游标：choice 的每个选项、text 的问题各占一个扁平项
  int _cursor = 0;

  bool get singleChoice =>
      questions.length == 1 &&
      questions.first.type == 'choice' &&
      !questions.first.multiSelect;

  /// 游标当前指向 (问题索引, 选项索引)；text 问题选项索引为 null
  (int, int?) get cursorInfo => _resolve(_cursor);

  void navigate(int delta) {
    final count = _flatItemCount;
    if (count == 0) return;
    _cursor = (_cursor + delta) % count;
    if (_cursor < 0) _cursor += count;
    notifyListeners();
  }

  /// Enter：单选选项 = 选中并要求提交；多选选项 = 仅切换；text = 提交。
  /// 返回 true 表示宿主应立即提交答案。
  bool confirmCurrent() {
    final (qi, oi) = _resolve(_cursor);
    if (qi < 0) return false;
    if (oi == -1) return true;
    final question = questions[qi];
    if (question.type == 'text') return true;
    if (oi == null) return true;
    if (question.multiSelect) {
      toggle(qi, oi);
      return false;
    }
    selectOnly(qi, oi);
    return true;
  }

  void toggle(int questionIndex, int optionIndex) {
    final set = _selections[questionIndex];
    set.contains(optionIndex) ? set.remove(optionIndex) : set.add(optionIndex);
    notifyListeners();
  }

  void selectOnly(int questionIndex, int optionIndex) {
    _selections[questionIndex] = {optionIndex};
    notifyListeners();
  }

  Set<int> selectionsOf(int questionIndex) => _selections[questionIndex];

  TextEditingController textCtrlOf(int questionIndex) => _textCtrls[questionIndex];

  /// 按问题索引组装答案：choice 取选中 label，text 取输入（空输入 = 空数组）
  List<List<String>> get answers => [
        for (var i = 0; i < questions.length; i++)
          questions[i].type == 'text'
              ? [
                  if (_textCtrls[i].text.trim().isNotEmpty)
                    _textCtrls[i].text.trim(),
                ]
              : [
                  for (final oi in _selections[i]) questions[i].options[oi].label,
                  if (_textCtrls[i].text.trim().isNotEmpty) _textCtrls[i].text.trim(),
                ],
      ];

  List<List<String>> get skippedAnswers =>
      [for (final _ in questions) <String>[]];

  int get _flatItemCount {
    var n = 0;
    for (final q in questions) {
      n += q.type == 'choice'
          ? q.options.length + 1 + (q.multiSelect ? 1 : 0)
          : 1;
    }
    return n;
  }

  (int, int?) _resolve(int flat) {
    var n = 0;
    for (var qi = 0; qi < questions.length; qi++) {
      final q = questions[qi];
      if (q.type == 'choice') {
        if (flat < n + q.options.length) return (qi, flat - n);
        if (q.multiSelect && flat == n + q.options.length) return (qi, -1);
        if (flat == n + q.options.length + (q.multiSelect ? 1 : 0)) return (qi, null);
        n += q.options.length + 1 + (q.multiSelect ? 1 : 0);
      } else {
        if (flat == n) return (qi, null);
        n += 1;
      }
    }
    return (-1, null);
  }

  @override
  void dispose() {
    for (final controller in _textCtrls) {
      controller.dispose();
    }
    super.dispose();
  }
}

class AgentQuestionPanel extends StatefulWidget {
  const AgentQuestionPanel({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onSkip,
  });

  final AgentQuestionPanelController controller;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;

  @override
  State<AgentQuestionPanel> createState() => _AgentQuestionPanelState();
}

class _AgentQuestionPanelState extends State<AgentQuestionPanel> {
  static const _fontFamily = ChatTheme.fontFamily;

  int? _hoverCursor;
  late final List<FocusNode> _textFocusNodes = [for (final _ in widget.controller.questions) FocusNode()];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AgentQuestionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final node in _textFocusNodes) node.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final (qi, oi) = widget.controller.cursorInfo;
    if (qi >= 0 && oi == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNodes[qi].requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = ChatTheme.of(context);
    return Container(
      // 与 CommandPalette 一致：间距随卡片一起出现/消失
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 360),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.line),
        boxShadow: theme.popShadows,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var qi = 0; qi < controller.questions.length; qi++) ...[
              if (qi > 0) const SizedBox(height: 10),
              _buildQuestion(controller.questions[qi], qi),
            ],
            const SizedBox(height: 4),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(AgentQuestion question, int qi) {
    final theme = ChatTheme.of(context);
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (question.header != null && question.header!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  // 琥珀主色系标签，与留痕卡的 header tag 同款（参考稿 .q-tag）
                  color: theme.accentSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  question.header!,
                  style: TextStyle(
                    color: theme.accentDeep,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(
                question.question,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.ink2,
                  fontSize: 12.5,
                  height: 1.55,
                  fontFamily: _fontFamily,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (question.type == 'choice') ...[
          for (var oi = 0; oi < question.options.length; oi++)
            _buildOption(question, qi, oi),
          if (question.multiSelect)
            Align(
              alignment: Alignment.centerLeft,
              child: _buildSubmitButton(qi),
            ),
          const SizedBox(height: 6),
          _buildTextField(question, qi, controller, hintText: '或输入自定义答案'),
        ]
        else
          _buildTextField(question, qi, controller),
      ],
    );
  }

  Widget _buildOption(AgentQuestion question, int qi, int oi) {
    final theme = ChatTheme.of(context);
    final controller = widget.controller;
    final selected = controller.selectionsOf(qi).contains(oi);
    final cursorHere = controller.cursorInfo == (qi, oi);
    final hovered = _hoverCursor == _flatIndexOf(qi, oi);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverCursor = _flatIndexOf(qi, oi)),
      onExit: (_) => setState(() => _hoverCursor = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (widget.controller.singleChoice) {
            controller.selectOnly(qi, oi);
            widget.onSubmit();
          } else if (question.multiSelect) {
            controller.toggle(qi, oi);
          } else {
            controller.selectOnly(qi, oi);
          }
        },
        child: Container(
          height: 32,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            // 选中/游标/hover 共用 hover 底色，选中额外加 line 内描边（参考稿 .opt.sel）
            color: selected || cursorHere || hovered
                ? theme.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? theme.line : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              if (question.multiSelect)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 15,
                    color: selected ? theme.ink : theme.ink3,
                  ),
                ),
              Text(
                question.options[oi].label,
                style: TextStyle(
                  color: selected ? theme.ink : theme.ink2,
                  fontSize: 13.5,
                  fontFamily: _fontFamily,
                ),
              ),
              if (question.options[oi].description?.isNotEmpty ?? false) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question.options[oi].description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.ink3,
                      fontSize: 12.5,
                      fontFamily: _fontFamily,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    AgentQuestion question,
    int qi,
    AgentQuestionPanelController controller, {
    String hintText = 'Type an answer',
  }) {
    final theme = ChatTheme.of(context);
    final cursorHere = controller.cursorInfo == (qi, null);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: theme.sunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cursorHere ? theme.line : theme.lineSoft,
        ),
      ),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onSkip();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.arrowDown) {
            controller.navigate(event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
        controller: controller.textCtrlOf(qi),
        focusNode: _textFocusNodes[qi],
        cursorColor: theme.accentDeep,
        // 卡片内没有 choice 区块时才自动抢焦点，避免打断浏览
        autofocus: qi == 0 &&
            !controller.questions.any((q) => q.type == 'choice'),
        style: TextStyle(
          color: theme.ink,
          fontSize: 13.5,
          fontFamily: _fontFamily,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: TextStyle(color: theme.ink3, fontSize: 13.5, fontFamily: _fontFamily),
        ),
        onSubmitted: (_) => widget.onSubmit(),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final theme = ChatTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            '↑↓ 选择 · Enter 确认 · Esc 跳过',
            style: TextStyle(
              color: theme.ink3,
              fontSize: 12,
              fontFamily: _fontFamily,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(int qi) {
    final theme = ChatTheme.of(context);
    final controller = widget.controller;
    final cursorHere = controller.cursorInfo == (qi, -1);
    return SizedBox(
        width: double.infinity,
        height: 32,
        child: TextButton(
      onPressed: widget.onSubmit,
      style: TextButton.styleFrom(
        foregroundColor: theme.ink2,
        backgroundColor: cursorHere ? theme.hover : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.check_box_outline_blank, size: 15, color: theme.ink3),
              ),
              Text(
              '提交答案',
        style: TextStyle(
          fontSize: 13.5,
          fontFamily: _fontFamily,
        ),
              ),
            ],
          ),
        ),
    );
  }

  int _flatIndexOf(int qi, int? oi) {
    var n = 0;
    for (var i = 0; i < widget.controller.questions.length; i++) {
      final q = widget.controller.questions[i];
      if (i == qi) {
        if (oi == null) return n;
        if (oi == -1) return n + q.options.length;
        return n + oi;
      }
      n += q.type == 'choice'
          ? q.options.length + 1 + (q.multiSelect ? 1 : 0)
          : 1;
    }
    return 0;
  }
}

/// 已回答问题的留痕卡片（只读），嵌在 AI 气泡内，随会话落盘。
class QuestionRecordCard extends StatelessWidget {
  const QuestionRecordCard({
    super.key,
    required this.questions,
    required this.answers,
    this.skipped = false,
  });

  final List<AgentQuestion> questions;
  final List<List<String>> answers;
  final bool skipped;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    // 一问题一卡：顶部条放问题、内容区放回复（与代码块同构的两段式卡片）。
    // 多问题时纵向叠卡，不再挤在同一张卡里分行。
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var qi = 0; qi < questions.length; qi++) ...[
            if (qi > 0) const SizedBox(height: 6),
            _buildCard(qi, theme),
          ],
        ],
      ),
    );
  }

  /// 单张问答卡：顶部条（sunken 底 + 问题文本 + header 标签）+ 回复内容区
  Widget _buildCard(int qi, ChatThemeData theme) {
    final header = questions[qi].header;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // 参考稿 .qcard：raised 卡 + 12 圆角 + line 描边 + 卡片阴影
        color: theme.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.line),
        boxShadow: theme.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部条：问题全文（最多两行）+ header 小标签靠右
          Container(
            padding: const EdgeInsets.fromLTRB(11, 7, 10, 8),
            color: theme.barBg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    questions[qi].question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 12,
                      height: 1.45,
                      fontFamily: ChatTheme.fontFamily,
                    ),
                  ),
                ),
                if (header != null && header.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      // 琥珀主色系标签，与提问卡片的 header tag 同款
                      color: theme.accentSoft,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      header,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.accentDeep, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2, fontFamily: ChatTheme.fontFamily),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 内容区：用户回复
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 10, 9),
            child: _buildAnswerRow(qi, theme),
          ),
        ],
      ),
    );
  }

  /// 答案行：「用户回复：」前缀 ink3 + 答案 ink w600；跳过态整体降 ink3
  Widget _buildAnswerRow(int qi, ChatThemeData theme) {
    final answer = _answerText(qi);
    final skippedThis = answer == '已跳过';
    return Text.rich(
      TextSpan(
        text: '用户回复：',
        children: [
          TextSpan(
            text: answer,
            style: skippedThis
                ? null
                : TextStyle(color: theme.ink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: theme.ink3,
        fontSize: 12,
        fontFamily: ChatTheme.fontFamily,
      ),
    );
  }

  String _answerText(int qi) {
    if (skipped) return '已跳过';
    final list = qi < answers.length ? answers[qi] : const <String>[];
    return list.isEmpty ? '已跳过' : list.join('、');
  }
}
