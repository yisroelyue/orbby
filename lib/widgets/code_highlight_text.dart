import 'package:flutter/material.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:re_highlight/styles/github-dark.dart';

/// Only renders code text; the caller owns the header, gutter and scrolling.
class CodeHighlightText extends StatefulWidget {
  const CodeHighlightText({
    super.key,
    required this.source,
    required this.language,
    required this.style,
    required this.isDark,
  });

  final String source;
  final String language;
  final TextStyle style;
  final bool isDark;

  @override
  State<CodeHighlightText> createState() => _CodeHighlightTextState();
}

class _CodeHighlightTextState extends State<CodeHighlightText> {
  // Engine-local, read-only language registry; no cross-window state needed.
  static final _highlight = Highlight()..registerLanguages(builtinAllLanguages);
  // Bound synchronous parsing work while long answers stream into the UI.
  static const _maxHighlightLength = 20000;
  static final _lightColors = _colorsOnly(githubTheme);
  static final _darkColors = _colorsOnly(githubDarkTheme);

  TextSpan? _span;

  // Keep the host's font metrics and background, including diff/Markdown tokens.
  static Map<String, TextStyle> _colorsOnly(Map<String, TextStyle> theme) => {
    for (final entry in theme.entries)
      if (entry.key != 'root') entry.key: TextStyle(color: entry.value.color),
  };

  @override
  void didUpdateWidget(covariant CodeHighlightText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.language != widget.language ||
        oldWidget.style != widget.style ||
        oldWidget.isDark != widget.isDark) {
      _span = null;
    }
  }

  TextSpan _buildSpan() {
    final plain = TextSpan(text: widget.source, style: widget.style);
    final language = widget.language.trim().toLowerCase();
    if (language.isEmpty || widget.source.length > _maxHighlightLength) {
      return plain;
    }
    try {
      // The registry resolves aliases such as js, ts, py and sh.
      if (_highlight.getLanguage(language) == null) return plain;
      final result = _highlight.highlight(
        code: widget.source,
        language: language,
        ignoreIllegals: true,
      );
      final renderer = TextSpanRenderer(
        widget.style,
        widget.isDark ? _darkColors : _lightColors,
      );
      result.render(renderer);
      final span = renderer.span;
      // Never lose source text, including incomplete code during streaming.
      return span != null && span.toPlainText() == widget.source ? span : plain;
    } catch (_) {
      return plain;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(_span ??= _buildSpan(), style: widget.style);
  }
}
