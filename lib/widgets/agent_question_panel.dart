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
/// - 多问题逐题确认，全部确认后提交；空答案不会隐式跳过其他问题。
/// - 多选先切换选项，再确认本题；文本输入后 Enter 确认本题。
/// - 卡片内 Esc 交由宿主跳过整组提问。

class AgentQuestionPanelController extends ChangeNotifier {
  AgentQuestionPanelController({required this.questions}) {
    for (var qi = 0; qi < questions.length; qi++) {
      _selections.add(<int>{});
      final index = qi;
      final controller = TextEditingController();
      var previousText = controller.text;
      controller.addListener(() {
        if (controller.text != previousText) {
          previousText = controller.text;
          _confirmedQuestions.remove(index);
        }
      });
      _textCtrls.add(controller);
    }
  }

  final List<AgentQuestion> questions;

  final List<Set<int>> _selections = [];
  final List<TextEditingController> _textCtrls = [];
  final Set<int> _confirmedQuestions = {};

  /// 键盘导航游标：choice 的每个选项、text 的问题各占一个扁平项
  int _cursor = 0;

  /// 游标当前指向 (问题索引, 选项索引)；text 问题选项索引为 null
  (int, int?) get cursorInfo => _resolve(_cursor);

  void navigate(int delta) {
    final count = _flatItemCount;
    if (count == 0) return;
    _cursor = (_cursor + delta) % count;
    if (_cursor < 0) _cursor += count;
    notifyListeners();
  }

  /// Enter 只确认当前题；返回 true 时才允许宿主提交整组答案。
  bool confirmCurrent() {
    final (qi, oi) = _resolve(_cursor);
    if (qi < 0) return false;
    if (oi == -1 || oi == null) return confirmQuestion(qi);
    final question = questions[qi];
    if (question.multiSelect) {
      toggle(qi, oi);
      return false;
    }
    selectOnly(qi, oi);
    return confirmQuestion(qi);
  }

  bool confirmQuestion(int questionIndex) {
    if (answers[questionIndex].isEmpty) {
      focusItem(questionIndex, null);
      return false;
    }
    _confirmedQuestions.add(questionIndex);
    for (var offset = 1; offset <= questions.length; offset++) {
      final next = (questionIndex + offset) % questions.length;
      if (!_confirmedQuestions.contains(next) || answers[next].isEmpty) {
        final q = questions[next];
        focusItem(next, q.type == 'choice' && q.options.isNotEmpty ? 0 : null);
        return false;
      }
    }
    return true;
  }

  void focusItem(int questionIndex, int? optionIndex) {
    for (var flat = 0; flat < _flatItemCount; flat++) {
      if (_resolve(flat) == (questionIndex, optionIndex)) {
        _cursor = flat;
        notifyListeners();
        return;
      }
    }
  }

  void toggle(int questionIndex, int optionIndex) {
    _confirmedQuestions.remove(questionIndex);
    final set = _selections[questionIndex];
    set.contains(optionIndex) ? set.remove(optionIndex) : set.add(optionIndex);
    notifyListeners();
  }

  void selectOnly(int questionIndex, int optionIndex) {
    _confirmedQuestions.remove(questionIndex);
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
  final FocusNode _panelFocusNode = FocusNode();
  List<FocusNode> _textFocusNodes = [];
  List<GlobalKey> _questionKeys = [];

  void _resetQuestionNodes() {
    for (final node in _textFocusNodes) {
      node.dispose();
    }
    _textFocusNodes = [for (final _ in widget.controller.questions) FocusNode()];
    _questionKeys = [for (final _ in widget.controller.questions) GlobalKey()];
  }

  @override
  void initState() {
    super.initState();
    _resetQuestionNodes();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AgentQuestionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _resetQuestionNodes();
      _hoverCursor = null;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final node in _textFocusNodes) node.dispose();
    _panelFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final controller = widget.controller;
    final position = controller.cursorInfo;
    final (qi, oi) = position;
    if (qi < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller != controller ||
          controller.cursorInfo != position) return;
      if (oi == null) {
        _textFocusNodes[qi].requestFocus();
      } else {
        _panelFocusNode.requestFocus();
      }
      final context = _questionKeys[qi].currentContext;
      if (context != null) Scrollable.ensureVisible(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = ChatTheme.of(context);
    return Focus(
      focusNode: _panelFocusNode,
      onKeyEvent: (_, event) {
        if (!_panelFocusNode.hasPrimaryFocus || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          controller.navigate(event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          if (controller.confirmCurrent()) widget.onSubmit();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onSkip();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
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
      ),
    );
  }

  Widget _buildQuestion(AgentQuestion question, int qi) {
    final theme = ChatTheme.of(context);
    final controller = widget.controller;
    return Column(
      key: _questionKeys[qi],
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
          controller.focusItem(qi, oi);
          if (question.multiSelect) {
            controller.toggle(qi, oi);
          } else {
            controller.selectOnly(qi, oi);
            if (controller.confirmQuestion(qi)) widget.onSubmit();
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
        onTap: () => controller.focusItem(qi, null),
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
        onSubmitted: (_) {
          if (controller.confirmQuestion(qi)) widget.onSubmit();
        },
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
            widget.controller.questions.length > 1
                ? '↑↓ 选择 · Enter 确认本题并继续 · 空答案不提交 · Esc 跳过全部'
                : '↑↓ 选择 · Enter 确认 · Esc 跳过',
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
      onPressed: () {
        if (controller.confirmQuestion(qi)) widget.onSubmit();
      },
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
              controller.questions.length > 1 ? '确认本题并继续' : '提交答案',
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
    // 顶部间距归零：上方间距由容器链路给（工具行 top 2 + 用户气泡的回答
    // 间距 32），卡片只留与后续正文的下方 8；卡间距 12 保证多卡分组可辨。
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var qi = 0; qi < questions.length; qi++) ...[
            if (qi > 0) const SizedBox(height: 12),
            _buildCard(qi, theme),
          ],
        ],
      ),
    );
  }

  /// 单张问答卡：顶部条（sunken 底 + 问题文本 + header 标签）+ 回复内容区。
  /// 圆角结构刻意三层：阴影底色 → 描边叠最上层 → ClipRRect 裁内容。
  /// 不能用 Container(clipBehavior)：其裁剪半径 = 圆角减边框宽（12-1），
  /// barBg 顶条被裁的边缘与 12 的描边不同心，四角抗锯齿叠描边发虚（左上角尤明显）；
  /// 描边画在裁剪之后正好盖住裁剪边缘，两半径同心，角落干净。
  Widget _buildCard(int qi, ChatThemeData theme) {
    final header = questions[qi].header;
    final radius = BorderRadius.circular(12);
    return DecoratedBox(
      // 底色 + 阴影（参考稿 .qcard）。阴影须在裁剪层之外画，否则被 ClipRRect 裁掉
      decoration: BoxDecoration(
        color: theme.raised,
        borderRadius: radius,
        boxShadow: theme.cardShadows,
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: theme.line),
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
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
                          // 中性灰标签：留痕不与进行中提问卡片的琥珀 header tag 抢注意
                          color: theme.tagBg,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          header,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.tagFg, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2, fontFamily: ChatTheme.fontFamily),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 内容区：选项回显（choice 型有选项时）+ 虚线 + 用户回复（参考稿 .ask）
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 7, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var oi = 0; oi < questions[qi].options.length; oi++)
                      _buildRecordOption(qi, oi, theme),
                    if (questions[qi].options.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const _DashedDivider(),
                      const SizedBox(height: 7),
                    ],
                    _buildAnswerRow(qi, theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选项回显行：字母徽标（A/B/C…）+ 选项文字。答案命中的选项 ink/w600
  /// 强调 + 绿色徽标（完成色语义：用户已选定的历史答案）；未命中整体 ink3。
  /// 跳过态不高亮任何选项。
  Widget _buildRecordOption(int qi, int oi, ChatThemeData theme) {
    final option = questions[qi].options[oi];
    final selected = !skipped &&
        qi < answers.length &&
        answers[qi].contains(option.label);
    final label = option.description == null || option.description!.isEmpty
        ? option.label
        : '${option.label}（${option.description}）';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? theme.okSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected ? theme.okSoft : theme.lineSoft,
              ),
            ),
            child: Text(
              String.fromCharCode(0x41 + oi),
              style: TextStyle(
                color: selected ? theme.ok : theme.ink3,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1,
                fontFamily: ChatTheme.fontFamily,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? theme.ink : theme.ink3,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                fontFamily: ChatTheme.fontFamily,
              ),
            ),
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

/// 水平虚线分隔（参考稿 .ask-answer 的 dashed 边框）：按宽度铺 3px 小条。
/// 留痕卡选项回显与答案行之间的分隔。
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 7).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: 3,
              height: 1.5,
              decoration: BoxDecoration(
                color: theme.line,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      },
    );
  }
}
