import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';
import 'package:image/image.dart' as img;
import '../widgets/color_picker.dart';

class WatermarkScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final ui.Image? loadedImage;
  final String outputDir;
  final void Function(String) onStatusUpdate;
  final Future<void> Function(Future<bool> Function()) onProcess;

  const WatermarkScreen({
    super.key,
    required this.imagePath,
    required this.imageBytes,
    required this.loadedImage,
    required this.outputDir,
    required this.onStatusUpdate,
    required this.onProcess,
  });

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  bool _isTextWatermark = true;

  // Text watermark
  String _textContent = '水印文字';
  double _fontSize = 36;
  Color _textColor = Colors.white;

  // Image watermark
  String? _watermarkImagePath;
  String? _watermarkImageName;
  double _scale = 20; // 5-100

  // Common
  int _position = 8; // bottom-right
  double _opacity = 70; // 10-100

  static const _positionLabels = ['左上','中上','右上','左中','居中','右中','左下','中下','右下'];

  String get _hexTextColor {
    final v = _textColor.toARGB32().toRadixString(16).padLeft(8, '0');
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

  Future<void> _pickWatermarkImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _watermarkImagePath = result.files.first.path;
      _watermarkImageName = result.files.first.name;
    });
  }

  Future<bool> _doProcess() async {
    if (widget.imagePath == null) return false;
    try {
      final opacity = _opacity / 100;
      if (_isTextWatermark) {
        final result = await ImageProcessor.addTextWatermark(
          inputPath: widget.imagePath!,
          outputDir: widget.outputDir,
          text: _textContent,
          fontSize: _fontSize,
          textColor: _toImgColor(_textColor),
          position: _position,
          opacity: opacity,
        );
        widget.onStatusUpdate('文字水印添加完成: ${result.width}×${result.height}');
      } else {
        if (_watermarkImagePath == null) {
          widget.onStatusUpdate('请先选择水印图片');
          return false;
        }
        final result = await ImageProcessor.addImageWatermark(
          inputPath: widget.imagePath!,
          outputDir: widget.outputDir,
          watermarkPath: _watermarkImagePath!,
          scale: _scale / 100,
          position: _position,
          opacity: opacity,
        );
        widget.onStatusUpdate('图片水印添加完成: ${result.width}×${result.height}');
      }
      return true;
    } catch (e) {
      widget.onStatusUpdate('水印添加失败: $e');
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
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('文字水印'), icon: Icon(Icons.text_fields)),
                    ButtonSegment(value: false, label: Text('图片水印'), icon: Icon(Icons.image)),
                  ],
                  selected: {_isTextWatermark},
                  onSelectionChanged: (v) => setState(() => _isTextWatermark = v.first),
                ),
                const SizedBox(height: 16),
                if (_isTextWatermark) _buildTextSettings(theme) else _buildImageSettings(theme),
                const SizedBox(height: 16), const Divider(), const SizedBox(height: 8),
                Text('通用设置', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Text('位置', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: GridView.count(
                    crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4,
                    childAspectRatio: 2.5,
                    children: List.generate(9, (i) {
                      final sel = _position == i;
                      return GestureDetector(
                        onTap: () => setState(() => _position = i),
                        child: Container(
                          decoration: BoxDecoration(
                            color: sel ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: sel ? theme.colorScheme.primary : Colors.grey[300]!, width: sel ? 2 : 1),
                          ),
                          alignment: Alignment.center,
                          child: Text(_positionLabels[i], style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: sel ? theme.colorScheme.onPrimaryContainer : null, fontSize: 12)),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [const Text('透明度: '), Text('${_opacity.round()}%', style: const TextStyle(fontWeight: FontWeight.bold))]),
                Slider(value: _opacity, min: 10, max: 100, divisions: 90, label: '${_opacity.round()}%', onChanged: (v) => setState(() => _opacity = v)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: hasImage ? () => widget.onProcess(_doProcess) : null,
                  icon: const Icon(Icons.branding_watermark),
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

  Widget _buildTextSettings(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文字水印设置', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: '文字内容', border: OutlineInputBorder(), isDense: true),
              controller: TextEditingController(text: _textContent),
              onChanged: (v) => _textContent = v.isEmpty ? '水印文字' : v,
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('字号: '),
              Expanded(child: Slider(value: _fontSize, min: 8, max: 200, divisions: 192, label: '${_fontSize.round()}pt', onChanged: (v) => setState(() => _fontSize = v))),
              SizedBox(width: 50, child: Text('${_fontSize.round()}pt', style: const TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Text('文字颜色: '), const SizedBox(width: 8),
              ColorPickerButton(color: _textColor, onChanged: (c) => setState(() => _textColor = c)),
              const SizedBox(width: 8),
              Text(_hexTextColor.toUpperCase(), style: theme.textTheme.bodySmall),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSettings(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('图片水印设置', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _pickWatermarkImage, icon: const Icon(Icons.folder_open), label: Text(_watermarkImageName ?? '选择水印图片')),
            if (_watermarkImageName != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Text('缩放比例: '),
                Expanded(child: Slider(value: _scale, min: 5, max: 100, divisions: 95, label: '${_scale.round()}%', onChanged: (v) => setState(() => _scale = v))),
                SizedBox(width: 50, child: Text('${_scale.round()}%', style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              Text('(相对于原图宽度)', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
