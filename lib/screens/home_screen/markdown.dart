part of 'home_screen.dart';

/// Markdown 渲染：气泡内 MarkdownBody 的样式表、代码块自定义渲染
/// （语言标签 + 复制按钮 + 横向滚动）。配色全部取当前主题 token。
extension _HomeScreenMarkdown on _HomeScreenState {
  /// MarkdownBody 样式表：Agent 正文 body 色、行内代码灰底 chip
  /// （底色由 _InlineCodeBuilder 画，样式表只出字体）、
  /// 代码块背景与父容器一致。
  MarkdownStyleSheet _markdownStyleSheet() {
    final theme = _themeData;
    return MarkdownStyleSheet(
      p: TextStyle(
        color: theme.body,
        fontSize: _bodyFontSize,
        height: _bodyLineHeightFactor,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w400,
        fontFamily: _fontFamily,
      ),
      h1: TextStyle(
        color: theme.ink,
        fontSize: 19,
        letterSpacing: 0.1,
        fontWeight: FontWeight.bold,
        fontFamily: _fontFamily,
      ),
      h1Padding: const EdgeInsets.only(top: 24, bottom: 12),
      h2: TextStyle(
        color: theme.ink,
        fontSize: 17,
        letterSpacing: 0.1,
        fontWeight: FontWeight.bold,
        fontFamily: _fontFamily,
      ),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
      h3: TextStyle(
        color: theme.ink,
        fontSize: 16,
        letterSpacing: 0.1,
        fontWeight: FontWeight.bold,
        fontFamily: _fontFamily,
      ),
      h3Padding: const EdgeInsets.only(top: 18, bottom: 8),
      h4Padding: const EdgeInsets.only(top: 16, bottom: 8),
      h5Padding: const EdgeInsets.only(top: 16, bottom: 8),
      h6Padding: const EdgeInsets.only(top: 16, bottom: 8),
      listBullet: TextStyle(
        color: theme.ink,
        fontSize: _bodyFontSize,
        fontFamily: _fontFamily,
      ),
      code: TextStyle(
        color: theme.body,
        fontSize: 13.5,
        height: 1.4,
        fontFamily: _codeFont,
        fontFamilyFallback: [_fontFamily],
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.lineSoft),
      ),
      a: TextStyle(
        color: theme.info,
        letterSpacing: 0.5,
        fontFamily: _fontFamily,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.sunken,
        border: Border(
          left: BorderSide(color: theme.line, width: 3),
        ),
      ),
      blockquotePadding:
          const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 8),
      // 表格与正文共用 surface 底色，通过圆角描边和表头区分层次。
      // 表头 barBg 灰带（随容器圆角裁剪）+ 中等字重，
      // 无竖线，仅表体行间横向 hairline，单元格宽松内边距。
      // tableHeadDecoration / tableDecoration 是本地 fork 包加的能力
      // （上游硬编码表头行无装饰、Table 无整体容器）
      tableHead: TextStyle(
        color: theme.ink,
        fontSize: 14,
        height: 1.65,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w600,
        fontFamily: _fontFamily,
      ),
      // 上游 fallback 默认居中，须显式改左对齐
      tableHeadAlign: TextAlign.left,
      tableBody: TextStyle(
        color: theme.body,
        fontSize: 14,
        height: 1.65,
        letterSpacing: 0.5,
        fontFamily: _fontFamily,
      ),
      tablePadding: const EdgeInsets.symmetric(vertical: 16),
      tableBorder: TableBorder(
        horizontalInside: BorderSide(
          color: theme.isDark ? const Color(0x59D8DADF) : theme.lineSoft,
          width: 1,
        ),
      ),
      tableCellsPadding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      // 整表容器：surface 底 + line 描边 + 10px 圆角，表头灰带等内容
      // 由 fork 侧按该圆角裁剪
      tableDecoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.isDark ? const Color(0x59D8DADF) : theme.line,
        ),
      ),
      tableHeadDecoration: BoxDecoration(
        color: theme.isDark
            ? const Color(0x26D8DADF)
            : Color.alphaBlend(const Color(0x08000000), theme.barBg),
      ),
      tableCellsDecoration: const BoxDecoration(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.line, width: 1),
        ),
      ),
    );
  }
}

/// 代码块：无边框的「语言标签 + 复制按钮」顶栏，下接独立的代码容器。
/// 顶栏仅顶部圆角，代码容器仅底部圆角并带 line-soft 描边，拼接处为直角。
/// 外层块样式经 builders['pre'] 全量接管，主题 token 由宿主传入。
class _PreTextBuilder extends MarkdownElementBuilder {
  _PreTextBuilder({required this.theme});

  final ChatThemeData theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().firstWhere(
          (child) => child.tag == 'code',
          orElse: () => element,
        );
    final classes = code?.attributes['class'] ?? '';
    final language = classes.startsWith('language-')
        ? classes.substring('language-'.length)
        : '';
    final source = element.textContent;

    final codeStyle = TextStyle(
      color: theme.body,
      fontSize: 13.5,
      height: 1.8,
      fontFamily: _codeFont,
      fontFamilyFallback: [_fontFamily],
    );

    // 行号：只弱化颜色，字号与行高倍数必须与 [codeStyle] 完全一致——行高是
    // 倍数、随字号变，两处一旦不同行号就会逐行漂移。末尾换行多切出的空串
    // 不计行号（与编辑器习惯一致）。
    final lines = source.split('\n');
    final lineCount =
        lines.isNotEmpty && lines.last.isEmpty ? lines.length - 1 : lines.length;
    // 只覆盖颜色：字号/行高/字体全部继承 codeStyle，才不会写着写着就不齐
    final gutterStyle = codeStyle.copyWith(color: theme.ink3);

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.only(left: 11, right: 8),
            decoration: BoxDecoration(
              color: theme.barBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                if (language.isNotEmpty)
                  Text(
                    language.toUpperCase(),
                    style: codeStyle.copyWith(
                      fontSize: 11.5,
                      letterSpacing: 0.8,
                      color: theme.isDark ? theme.body : theme.ink3,
                    ),
                  ),
                const Spacer(),
                _CodeCopyButton(theme: theme, source: source),
              ],
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
              border: Border.all(color: theme.lineSoft),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 行号列：固定在左侧、不随代码横向滚动（与编辑器一致），
                // 宽度由最长行号自然撑开
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8, top: 6, bottom: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 1; i <= lineCount; i++)
                        Text('$i', style: gutterStyle),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
                    child: CodeHighlightText(
                      source: source,
                      language: language,
                      style: codeStyle,
                      isDark: theme.isDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 行内代码（正文 `片段`）：codeInlineBg 灰底 chip，内边距让底色比文字
/// 大一圈。TextStyle.background 的 Paint 画的底色紧贴文字行盒、无法加
/// 内边距，故经 builders['code'] 接管为独立 Widget（段落是 Wrap 布局，
/// 与相邻文字混排，同 img 的机制）。
/// 代码块的内层 code 必含换行（CodeSyntax 会把行内代码的换行替换成
/// 空格），据此返回 null 交还给 _PreTextBuilder，防代码块内容重复渲染。
class _InlineCodeBuilder extends MarkdownElementBuilder {
  _InlineCodeBuilder({required this.theme});

  final ChatThemeData theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final source = element.textContent;
    if (source.contains('\n')) return null;
    return Container(
      // Wrap 换行时保留灰底之间的空隙，表格单元格内同样生效。
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: theme.codeInlineBg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        source,
        // 与默认渲染同向 merge 父级样式（加粗/斜体/letterSpacing 会继承到
        // 行内代码上）；兜底仅防御 styles['code'] 缺失
        style: parentStyle?.merge(preferredStyle) ??
            preferredStyle ??
            TextStyle(color: theme.body, fontSize: 13.5, fontFamily: _codeFont),
      ),
    );
  }
}

class _CodeCopyButton extends StatefulWidget {
  const _CodeCopyButton({required this.theme, required this.source});

  final ChatThemeData theme;
  final String source;

  @override
  State<_CodeCopyButton> createState() => _CodeCopyButtonState();
}

class _CodeCopyButtonState extends State<_CodeCopyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Clipboard.setData(ClipboardData(text: widget.source)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered
                ? theme.ink.withValues(alpha: 0.08)
                : theme.ink.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SvgPicture.asset(
            'assets/svg/复制.svg',
            width: 13,
            height: 13,
            colorFilter: ColorFilter.mode(
              theme.isDark
                  ? Colors.white
                  : (_hovered ? theme.ink : theme.ink3),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}
