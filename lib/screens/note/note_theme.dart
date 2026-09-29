import 'package:flutter/material.dart';

/// 「笔记浮窗 · 密码本集成」设计 token。
/// 对照设计稿：panel #FCFBF9 / card #FFFFFF / ink #1F2A44 /
/// accent #FFC145 / danger #C0483C，卡圆角 12、编辑卡圆角 14。
abstract final class NoteColors {
  static const panel = Color(0xFFFCFBF9);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE7E3DB);
  static const lineSoft = Color(0xFFEFEBE4);
  static const cardBorder = Color(0xFFEFEBE4);
  static const cardBorderHover = Color(0xFFDEDAD1);
  static const editorBorder = Color(0xFFE3DFD6);
  static const ink = Color(0xFF1F2A44);
  static const ink2 = Color(0xFF5D6577);
  static const ink3 = Color(0xFF9AA1AF);
  static const body = Color(0xFF3F4557);
  static const accent = Color(0xFFFFC145);
  static const accentHover = Color(0xFFFFCB5C);
  static const accentDeep = Color(0xFF9C6E14);
  static const accentSoft = Color(0xFFFFF6E2);
  static const hover = Color(0xFFF3F5FA);
  static const danger = Color(0xFFC0483C);
  static const dangerSoft = Color(0xFFFBEDEA);
  static const chevron = Color(0xFFD3D7DF);
  static const windowBorder = Color(0x121F2A44);
}

/// 折叠行 / 密码条目行卡片（白底 12 圆角 + 细边 + 浅影）。
BoxDecoration noteCardDecoration({bool hover = false}) => BoxDecoration(
      color: NoteColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: hover ? NoteColors.cardBorderHover : NoteColors.cardBorder),
      boxShadow: hover
          ? const [
              BoxShadow(color: Color(0x1F1F2A44), blurRadius: 7, offset: Offset(0, 2), spreadRadius: -3),
            ]
          : const [
              BoxShadow(color: Color(0x0A1F2A44), blurRadius: 2, offset: Offset(0, 1)),
            ],
    );

/// 展开的编辑卡（14 圆角 + 深一档的投影）。
BoxDecoration noteEditorDecoration() => const BoxDecoration(
      color: NoteColors.card,
      borderRadius: BorderRadius.all(Radius.circular(14)),
      border: Border.fromBorderSide(BorderSide(color: NoteColors.editorBorder)),
      boxShadow: [
        BoxShadow(color: Color(0x0D1F2A44), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x291F2A44), blurRadius: 28, offset: Offset(0, 12), spreadRadius: -10),
      ],
    );

/// 悬停态构建器：折叠行边框 / 按钮底色随 hover 变化。
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool hover) builder;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _hover ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.builder(context, _hover),
    );
  }
}

/// 头部/行内小图标按钮。29×29 r9（small 26×26 r8），
/// active 态琥珀浅底 + 深琥珀图标，danger 态红字红底。
class IconAction extends StatefulWidget {
  const IconAction({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.color,
    this.active = false,
    this.danger = false,
    this.small = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final bool active;
  final bool danger;
  final bool small;

  @override
  State<IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<IconAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.small ? 26.0 : 29.0;
    final radius = widget.small ? 8.0 : 9.0;
    final iconSize = widget.small ? 15.0 : 17.0;
    final Color fg;
    final Color bg;
    if (widget.active) {
      fg = NoteColors.accentDeep;
      bg = NoteColors.accentSoft;
    } else if (widget.danger) {
      fg = NoteColors.danger;
      bg = _hover ? NoteColors.dangerSoft : Colors.transparent;
    } else {
      fg = widget.color ?? NoteColors.ink2;
      bg = _hover ? NoteColors.hover : Colors.transparent;
    }
    Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(widget.icon, size: iconSize, color: fg),
    );
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: child,
      ),
    );
  }
}

/// 文字操作按钮（展开卡底部：复制密码 / 编辑 / 删除）。
class TextAction extends StatefulWidget {
  const TextAction({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  State<TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<TextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.danger ? NoteColors.danger : NoteColors.ink2;
    final bg = _hover
        ? (widget.danger ? NoteColors.dangerSoft : NoteColors.hover)
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 29,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  letterSpacing: .2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 琥珀主按钮（底部「新建笔记 / 新建密码」、锁定态「解锁」）。
/// onTap 为 null 时为禁用态（半透明、不可点）。
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.width,
    this.height = 42,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final double? width;
  final double height;
  final IconData? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: !enabled
                ? NoteColors.accent.withValues(alpha: 0.45)
                : (_hover ? NoteColors.accentHover : NoteColors.accent),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Color(0x1A1F2A44), blurRadius: 2, offset: Offset(0, 1)),
              BoxShadow(color: Color(0x59FFFFFF), blurRadius: 0, offset: Offset(0, 1), spreadRadius: -1),
            ],
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon ?? Icons.add_rounded,
                  size: widget.icon != null ? 17 : 15,
                  color: NoteColors.ink,
                  weight: 900,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: NoteColors.ink,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空态占位：虚线边框 + 居中提示文字。
class DashedPlaceholder extends StatelessWidget {
  const DashedPlaceholder({super.key, required this.text, this.height = 120});

  final String text;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0x80FFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: CustomPaint(
        painter: _DashBorderPainter(),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: NoteColors.ink3,
              letterSpacing: .4,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NoteColors.editorBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const r = 12.0;
    final rect = Offset(0.5, 0.5) & Size(size.width - 1, size.height - 1);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(r)));
    // 沿路径等距取点画短划线
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final tangent = metric.getTangentForOffset(dist);
        if (tangent != null) {
          canvas.drawLine(
            tangent.position,
            tangent.position + tangent.vector * 4,
            paint,
          );
        }
        dist += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// logo：墨底圆角方块 + 三条横线（白 / 白 55% / 琥珀）。
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: NoteColors.ink,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x471F2A44), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size.square(size * 0.56),
          painter: _LogoLinesPainter(),
        ),
      ),
    );
  }
}

class _LogoLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint();
    void line(double y, double w, Color color) {
      paint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4 * s, y * s, w * s, 2.2 * s),
          Radius.circular(1.1 * s),
        ),
        paint,
      );
    }

    line(6, 16, Colors.white); // 白 · 宽 16
    line(10.9, 11, const Color(0x8CFFFFFF)); // 白 55% · 宽 11
    line(15.8, 15, NoteColors.accent); // 琥珀 · 宽 15
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
