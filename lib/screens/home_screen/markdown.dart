part of 'home_screen.dart';

/// Markdown 渲染：气泡内 MarkdownBody 的样式表、代码块自定义渲染
/// （语言标签 + 复制按钮 + 横向滚动）。
extension _HomeScreenMarkdown on _HomeScreenState {
  /// MarkdownBody 样式表：配色与字体统一取库级视觉常量
  MarkdownStyleSheet _markdownStyleSheet() {
    return MarkdownStyleSheet(
      p: TextStyle(
        color: _bubbleText,
        fontSize: 14,
        height: 1.4,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w400,
        fontFamily: _fontFamily,
      ),
      h1: TextStyle(
        color: _bubbleText,
        fontSize: 17,
        letterSpacing: 0.8,
        fontWeight: FontWeight.bold,
        fontFamily: _fontFamily,
      ),
      h1Padding: const EdgeInsets.only(top: 14, bottom: 6),
      h2: TextStyle(
        color: _bubbleText,
        fontSize: 15,
        letterSpacing: 0.8,
        fontWeight: FontWeight.bold,
        fontFamily: _fontFamily,
      ),
      h2Padding: const EdgeInsets.only(top: 12, bottom: 5),
      h3: TextStyle(
        color: _bubbleText,
        fontSize: 14,
        letterSpacing: 0.8,
        fontWeight: FontWeight.bold,
        fontFamily: _fontFamily,
      ),
      h3Padding: const EdgeInsets.only(top: 10, bottom: 4),
      code: TextStyle(
        color: _codeText,
        fontSize: 13,
        fontFamily: _codeFont,
        fontFamilyFallback: [_fontFamily],
      ),
      codeblockDecoration: BoxDecoration(
        color: _codeBlockBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      a: TextStyle(
        color: _linkText,
        letterSpacing: 0.8,
        fontFamily: _fontFamily,
      ),
      blockquoteDecoration: BoxDecoration(
        color: _bubbleText.withValues(alpha: 0.05),
        border: Border(
          left: BorderSide(color: _dividerColor, width: 3),
        ),
      ),
      blockquotePadding:
          const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 8),
      tableHead: TextStyle(
        color: _bubbleText,
        fontSize: 13,
        letterSpacing: 0.8,
        fontWeight: FontWeight.bold,
        fontFamily: _fontFamily,
      ),
      tableBody: TextStyle(
        color: _bubbleText,
        fontSize: 13,
        letterSpacing: 0.8,
        fontFamily: _fontFamily,
      ),
      tablePadding: const EdgeInsets.symmetric(vertical: 16),
      tableBorder: TableBorder.all(color: _dividerColor, width: 1),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      tableCellsDecoration: const BoxDecoration(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _dividerColor, width: 1),
        ),
      ),
    );
  }
}

/// 代码块文字：只重写 visitText 换颜色，块的外层样式仍由样式表渲染
/// （flutter_markdown 没有单独的代码块文字样式字段，code 一个样式管行内+整块）
class _PreTextBuilder extends MarkdownElementBuilder {
  _PreTextBuilder(this.style);

  final TextStyle style;

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

    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: const Color(0xFF18212B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (language.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(language, style: style.copyWith(fontSize: 11, color: Colors.white54)),
                ),
              const Spacer(),
              _CodeCopyButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: source)),
              ),
            ],
          ),
          if (language.isNotEmpty)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 10,
              endIndent: 10,
              color: Color(0x265E7185),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Text(source, style: style),
          ),
        ],
      ),
    );
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(10),
      child: Text(text.text, style: style),
    );
  }
}

class _CodeCopyButton extends StatefulWidget {
  const _CodeCopyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CodeCopyButton> createState() => _CodeCopyButtonState();
}

class _CodeCopyButtonState extends State<_CodeCopyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 30,
          height: 30,
          alignment: Alignment.center,
          color: _hovered ? const Color(0x265E7185) : Colors.transparent,
          child: const Icon(Icons.copy, size: 15, color: Colors.white60),
        ),
      ),
    );
  }
}
