import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';
import 'package:image/image.dart' as img;
import '../widgets/color_picker.dart';

class CanvasExpandScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final ui.Image? loadedImage;
  final String outputDir;
  final void Function(String) onStatusUpdate;
  final Future<void> Function(Future<bool> Function()) onProcess;

  const CanvasExpandScreen({
    super.key,
    required this.imagePath,
    required this.imageBytes,
    required this.loadedImage,
    required this.outputDir,
    required this.onStatusUpdate,
    required this.onProcess,
  });

  @override
  State<CanvasExpandScreen> createState() => _CanvasExpandScreenState();
}

class _CanvasExpandScreenState extends State<CanvasExpandScreen> {
  bool _unifiedMargin = true;
  int _margin = 50;
  int _marginTop = 50, _marginBottom = 50, _marginLeft = 50, _marginRight = 50;
  Color _expandColor = Colors.white;

  String get _hexColor {
    final v = _expandColor.toARGB32().toRadixString(16).padLeft(8, '0');
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
      final result = await ImageProcessor.expandCanvas(
        inputPath: widget.imagePath!,
        outputDir: widget.outputDir,
        top: _unifiedMargin ? _margin : _marginTop,
        bottom: _unifiedMargin ? _margin : _marginBottom,
        left: _unifiedMargin ? _margin : _marginLeft,
        right: _unifiedMargin ? _margin : _marginRight,
        color: _toImgColor(_expandColor),
      );
      widget.onStatusUpdate('扩图完成: ${result.width}×${result.height}');
      return true;
    } catch (e) {
      widget.onStatusUpdate('扩图失败: $e');
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
        // Left: Image preview
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.grey[200],
            child: hasImage && widget.imageBytes != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(widget.imageBytes!, fit: BoxFit.contain),
                      ),
                    ),
                  )
                : const Center(
                    child: Text('请选择图片', style: TextStyle(color: Colors.grey)),
                  ),
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
                if (hasImage && widget.loadedImage != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.photo_size_select_large, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Text('原始尺寸: ${widget.loadedImage!.width}×${widget.loadedImage!.height}', style: theme.textTheme.titleSmall),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('边距模式', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [ButtonSegment(value: true, label: Text('统一')), ButtonSegment(value: false, label: Text('独立'))],
                      selected: {_unifiedMargin},
                      onSelectionChanged: (v) => setState(() => _unifiedMargin = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_unifiedMargin)
                  _buildMarginField('边距 (px)', _margin, (v) => setState(() => _margin = (int.tryParse(v) ?? 0).clamp(0, 10000)))
                else ...[
                  _buildMarginField('上边距 (px)', _marginTop, (v) => setState(() => _marginTop = (int.tryParse(v) ?? 0).clamp(0, 10000))),
                  const SizedBox(height: 8),
                  _buildMarginField('下边距 (px)', _marginBottom, (v) => setState(() => _marginBottom = (int.tryParse(v) ?? 0).clamp(0, 10000))),
                  const SizedBox(height: 8),
                  _buildMarginField('左边距 (px)', _marginLeft, (v) => setState(() => _marginLeft = (int.tryParse(v) ?? 0).clamp(0, 10000))),
                  const SizedBox(height: 8),
                  _buildMarginField('右边距 (px)', _marginRight, (v) => setState(() => _marginRight = (int.tryParse(v) ?? 0).clamp(0, 10000))),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('扩展区域颜色:', style: theme.textTheme.titleMedium),
                    const SizedBox(width: 12),
                    ColorPickerButton(color: _expandColor, onChanged: (c) => setState(() => _expandColor = c)),
                    const SizedBox(width: 8),
                    Text(_hexColor.toUpperCase(), style: theme.textTheme.bodySmall),
                  ],
                ),
                if (hasImage && widget.loadedImage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('扩展后尺寸', style: theme.textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(_getResultSize(), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: hasImage ? () => widget.onProcess(_doProcess) : null,
                  icon: const Icon(Icons.open_with),
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

  String _getResultSize() {
    if (widget.loadedImage == null) return '';
    final t = _unifiedMargin ? _margin : _marginTop;
    final b = _unifiedMargin ? _margin : _marginBottom;
    final l = _unifiedMargin ? _margin : _marginLeft;
    final r = _unifiedMargin ? _margin : _marginRight;
    return '${widget.loadedImage!.width + l + r}×${widget.loadedImage!.height + t + b}';
  }

  Widget _buildMarginField(String label, int value, ValueChanged<String> onChanged) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      keyboardType: TextInputType.number,
      controller: TextEditingController(text: value.toString()),
      onChanged: onChanged,
    );
  }
}
