import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';
import 'package:image/image.dart' as img;
import '../widgets/color_picker.dart';

class BackgroundFillScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final ui.Image? loadedImage;
  final String outputDir;
  final void Function(String) onStatusUpdate;
  final Future<void> Function(Future<bool> Function()) onProcess;

  const BackgroundFillScreen({
    super.key,
    required this.imagePath,
    required this.imageBytes,
    required this.loadedImage,
    required this.outputDir,
    required this.onStatusUpdate,
    required this.onProcess,
  });

  @override
  State<BackgroundFillScreen> createState() => _BackgroundFillScreenState();
}

class _BackgroundFillScreenState extends State<BackgroundFillScreen> {
  Color _fillColor = Colors.white;

  String get _hexColor {
    final v = _fillColor.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${v.substring(2)}${v.substring(0, 2)}';
  }

  img.Color _toImgColor(Color c) {
    return img.ColorUint8.rgba(
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
      (c.a * 255).round(),
    );
  }

  Future<bool> _doProcess() async {
    if (widget.imagePath == null) return false;
    try {
      final result = await ImageProcessor.fillBackground(
        inputPath: widget.imagePath!,
        outputDir: widget.outputDir,
        color: _toImgColor(_fillColor),
      );
      widget.onStatusUpdate('背景填充完成: ${result.width}×${result.height}');
      return true;
    } catch (e) {
      widget.onStatusUpdate('填充失败: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imagePath != null;
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Image preview with checkerboard
        Expanded(
          flex: 5,
          child: Container(
            color: const Color(0xFF2A2A2A),
            child: hasImage && widget.loadedImage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: CustomPaint(
                            painter: _CheckerboardPainter(),
                            child: Center(
                              child: RawImage(image: widget.loadedImage, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const Center(child: Text('请选择图片', style: TextStyle(color: Color(0xFF757575)))),
          ),
        ),
        // Right: Configuration panel
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasImage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('棋盘格表示透明区域，将被填充为所选颜色', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('填充颜色', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ColorPickerButton(color: _fillColor, onChanged: (c) => setState(() => _fillColor = c)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('十六进制: $_hexColor', style: theme.textTheme.bodyMedium),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4, runSpacing: 4,
                                    children: [Colors.white, Colors.black, Colors.red, Colors.green, Colors.blue, Colors.yellow, Colors.grey]
                                        .map((c) {
                                      final sel = _fillColor.toARGB32() == c.toARGB32();
                                      return GestureDetector(
                                        onTap: () => setState(() => _fillColor = c),
                                        child: Container(
                                          width: 24, height: 24,
                                          decoration: BoxDecoration(
                                            color: c, shape: BoxShape.circle,
                                            border: Border.all(
                                              color: sel ? theme.colorScheme.primary : Colors.grey[400]!,
                                              width: sel ? 2.5 : 1,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (hasImage && widget.loadedImage != null)
                  Text(
                    '图片尺寸: ${widget.loadedImage!.width}×${widget.loadedImage!.height} | 输出为不透明RGB图像',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: hasImage ? () => widget.onProcess(_doProcess) : null,
                  icon: const Icon(Icons.format_color_fill),
                  label: const Text('开始处理'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color = const Color(0xFFCCCCCC);
    final p2 = Paint()..color = const Color(0xFFFFFFFF);
    const t = 10.0;
    for (double y = 0; y < size.height; y += t) {
      for (double x = 0; x < size.width; x += t) {
        final even = ((x / t).floor() + (y / t).floor()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, t, t), even ? p1 : p2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
