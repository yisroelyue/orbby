import 'package:flutter/material.dart';

/// A small circular color preview button that opens a color picker dialog.
class ColorPickerButton extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  final double size;

  const ColorPickerButton({
    super.key,
    required this.color,
    required this.onChanged,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showColorPicker(context),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[400]!, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showColorPicker(BuildContext context) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(initialColor: color),
    );
    if (result != null) {
      onChanged(result);
    }
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerDialog({required this.initialColor});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _value;
  late double _alpha;
  final bool _showAlpha = true;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _alpha = hsv.alpha;
  }

  Color get _currentColor => HSVColor.fromAHSV(_alpha, _hue, _saturation, _value).toColor();

  String _colorToHex(Color c) {
    final v = c.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${v.substring(2)}${v.substring(0, 2)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择颜色'),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Saturation-Value picker area
              GestureDetector(
                onPanStart: (d) => _updateSV(d.localPosition),
                onPanUpdate: (d) => _updateSV(d.localPosition),
                child: Container(
                  width: 260,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: CustomPaint(
                    painter: _SVPainter(hue: _hue),
                  ),
                ),
              ),

              // Hue slider
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('色相', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 16,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                      ),
                      child: Slider(
                        value: _hue,
                        min: 0,
                        max: 360,
                        onChanged: (v) => setState(() => _hue = v),
                      ),
                    ),
                  ),
                ],
              ),
              // Build hue track with rainbow gradient
              Container(
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),

              // Alpha slider
              if (_showAlpha) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('透明度', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _alpha,
                        min: 0,
                        max: 1,
                        onChanged: (v) => setState(() => _alpha = v),
                      ),
                    ),
                    Text('${(_alpha * 100).round()}%', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],

              // Preview
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _currentColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    // Checkerboard behind for alpha
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _colorToHex(_currentColor),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    ),
                  ),
                ],
              ),

              // Quick presets
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Colors.white,
                  Colors.black,
                  Colors.red,
                  Colors.green,
                  Colors.blue,
                  Colors.yellow,
                  Colors.orange,
                  Colors.purple,
                  Colors.transparent,
                ].map((c) {
                  return GestureDetector(
                    onTap: () {
                      final hsv = HSVColor.fromColor(c);
                      setState(() {
                        _hue = hsv.hue;
                        _saturation = hsv.saturation;
                        _value = hsv.value;
                        _alpha = hsv.alpha;
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _currentColor),
          child: const Text('确认'),
        ),
      ],
    );
  }

  void _updateSV(Offset localPos) {
    // The SV widget is 260x200
    setState(() {
      _saturation = (localPos.dx / 260).clamp(0.0, 1.0);
      _value = 1.0 - (localPos.dy / 200).clamp(0.0, 1.0);
    });
  }
}

class _SVPainter extends CustomPainter {
  final double hue;

  _SVPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    // Saturation-Value gradient for a given hue
    for (double y = 0; y < size.height; y++) {
      for (double x = 0; x < size.width; x++) {
        final s = x / size.width;
        final v = 1.0 - y / size.height;
        final color = HSVColor.fromAHSV(1.0, hue, s, v);
        final paint = Paint()..color = color.toColor();
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
      }
    }
    // Selection cursor
    // (cursor is drawn by overlay, so just draw the gradient here)
  }

  @override
  bool shouldRepaint(covariant _SVPainter oldDelegate) => oldDelegate.hue != hue;
}
