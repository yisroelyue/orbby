import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_question.dart';

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
      n += q.type == 'choice' ? q.options.length + 1 : 1;
    }
    return n;
  }

  (int, int?) _resolve(int flat) {
    var n = 0;
    for (var qi = 0; qi < questions.length; qi++) {
      final q = questions[qi];
      if (q.type == 'choice') {
        if (flat < n + q.options.length) return (qi, flat - n);
        if (flat == n + q.options.length) return (qi, null);
        n += q.options.length + 1;
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
  static const _fontFamily = 'Sarasa Mono SC';

  static const _bg = Color(0xFF1E1E1E);
  static const _selectedBg = Color(0x24FFFFFF);
  static const _hoverBg = Color(0x12FFFFFF);
  static const _mainText = Color(0xFFEAEAEA);
  static const _descText = Color(0x73FFFFFF);
  static const _fieldBg = Color(0xFF161616);

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
    return Container(
      // 与 CommandPalette 一致：间距随卡片一起出现/消失
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (question.header != null && question.header!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: Text(
                  question.header!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                question.question,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _mainText,
                  fontSize: 13,
                  fontFamily: _fontFamily,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (question.type == 'choice') ...[
          for (var oi = 0; oi < question.options.length; oi++)
            _buildOption(question, qi, oi),
          const SizedBox(height: 5),
          _buildTextField(question, qi, controller, hintText: '或输入自定义答案'),
        ]
        else
          _buildTextField(question, qi, controller),
      ],
    );
  }

  Widget _buildOption(AgentQuestion question, int qi, int oi) {
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? _selectedBg
                : cursorHere || hovered
                    ? _hoverBg
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
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
                    color: selected ? _mainText : _descText,
                  ),
                ),
              Text(
                question.options[oi].label,
                style: TextStyle(
                  color: _mainText,
                  fontSize: 13,
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
                      color: _descText,
                      fontSize: 12,
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
    final cursorHere = controller.cursorInfo == (qi, null);
    return Container(
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: cursorHere ? 0.24 : 0.08),
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
        cursorColor: Colors.white,
        // 卡片内没有 choice 区块时才自动抢焦点，避免打断浏览
        autofocus: qi == 0 &&
            !controller.questions.any((q) => q.type == 'choice'),
        style: TextStyle(
          color: _mainText,
          fontSize: 13,
          fontFamily: _fontFamily,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          border: InputBorder.none,
          hintText: hintText,
        ),
        onSubmitted: (_) => widget.onSubmit(),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final controller = widget.controller;
    return Row(
      children: [
        Expanded(
          child: Text(
            '↑↓ 选择 · Enter 确认 · Esc 跳过',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: 11,
              fontFamily: _fontFamily,
            ),
          ),
        ),
      ],
    );
  }

  int _flatIndexOf(int qi, int? oi) {
    var n = 0;
    for (var i = 0; i < widget.controller.questions.length; i++) {
      final q = widget.controller.questions[i];
      if (i == qi) return oi == null ? n : n + oi;
      n += q.type == 'choice' ? q.options.length + 1 : 1;
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
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF202328),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var qi = 0; qi < questions.length; qi++) ...[
            if (qi > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (questions[qi].header != null && questions[qi].header!.isNotEmpty) ...[
                  Container(
                    constraints: const BoxConstraints(maxWidth: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                    ),
                    child: Text(
                      questions[qi].header!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Sarasa Mono SC'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: questions[qi].question,
                      children: [TextSpan(text: skipped ? '  ·  skipped' : '  ·  ${_answerText(qi)}')],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontFamily: 'Sarasa Mono SC',
                    ),
                  ),
                ),
              ],
            ),
            if (false) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text.rich(
                TextSpan(
                  text: skipped ? '已跳过' : '回答：',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: skipped ? 0.35 : 0.45),
                    fontSize: 12,
                    fontFamily: 'Sarasa Mono SC',
                  ),
                  children: [
                    if (!skipped)
                      TextSpan(
                        text: _answerText(qi),
                        style: const TextStyle(
                          color: Color(0xFFEAEAEA),
                          fontSize: 12,
                          fontFamily: 'Sarasa Mono SC',
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ],
          ],
        ],
      ),
    );
  }

  String _answerText(int qi) {
    if (skipped) return '已跳过';
    final list = qi < answers.length ? answers[qi] : const <String>[];
    return list.isEmpty ? '已跳过' : list.join('、');
  }
}
