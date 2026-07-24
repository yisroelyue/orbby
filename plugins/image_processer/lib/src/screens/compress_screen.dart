import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';
import 'package:path/path.dart' as p;

class CompressScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final String outputDir;
  final void Function(String) onStatusUpdate;
  final Future<void> Function(Future<bool> Function()) onProcess;

  const CompressScreen({
    super.key,
    required this.imagePath,
    required this.imageBytes,
    required this.outputDir,
    required this.onStatusUpdate,
    required this.onProcess,
  });

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  int _quality = 80;
  bool _enableResize = false;
  int? _maxWidth;
  int? _maxHeight;
  bool _keepAspectRatio = true;
  String _outputFormat = 'auto';

  static const _formats = ['auto', 'jpg', 'webp', 'png'];

  bool get _showsQuality => _outputFormat != 'png';

  Future<bool> _doProcess() async {
    if (widget.imagePath == null) return false;

    try {
      final result = await ImageProcessor.compress(
        inputPath: widget.imagePath!,
        outputDir: widget.outputDir,
        quality: _quality,
        maxWidth: _enableResize ? _maxWidth : null,
        maxHeight: _enableResize ? _maxHeight : null,
        keepAspectRatio: _keepAspectRatio,
        outputFormat: _outputFormat == 'auto' ? null : _outputFormat,
      );

      // Get file sizes for comparison
      final originalSize = await File(widget.imagePath!).length();
      final compressedSize = await File(result.outputPath).length();
      final ratio = CompressProcessor.getCompressionRatio(originalSize, compressedSize);

      widget.onStatusUpdate(
        '压缩完成: ${result.width}×${result.height} | '
        '${_formatSize(originalSize)} → ${_formatSize(compressedSize)} '
        '(节省 ${ratio.toStringAsFixed(1)}%)',
      );
      return true;
    } catch (e) {
      widget.onStatusUpdate('压缩失败: $e');
      return false;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
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
            color: const Color(0xFF2A2A2A),
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
                    child: Text('请选择图片', style: TextStyle(color: Color(0xFF757575))),
                  ),
          ),
        ),
        // Right: Configuration panel
        Container(
          width: 300,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current image info
                if (hasImage)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.image, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.basename(widget.imagePath!), style: theme.textTheme.titleSmall),
                                Text(
                                  '当前格式: ${p.extension(widget.imagePath!).replaceAll('.', '').toUpperCase()}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Output format
                Text('输出格式', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _formats.map((fmt) {
                    final selected = _outputFormat == fmt;
                    return ChoiceChip(
                      label: Text(fmt == 'auto' ? '自动' : fmt.toUpperCase()),
                      selected: selected,
                      onSelected: hasImage ? (v) => setState(() => _outputFormat = fmt) : null,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Quality slider
                if (_showsQuality) ...[
                  Text('压缩质量: $_quality%', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    _quality < 30 ? '极高压缩' : _quality < 60 ? '高压缩' : _quality < 80 ? '中等' : '低压缩',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  Slider(
                    value: _quality.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    label: '$_quality%',
                    onChanged: hasImage ? (v) => setState(() => _quality = v.round()) : null,
                  ),
                  const SizedBox(height: 8),
                ],

                // Resize options
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    title: Text('调整尺寸', style: theme.textTheme.titleMedium),
                    value: _enableResize,
                    onChanged: hasImage ? (v) => setState(() => _enableResize = v) : null,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),

                if (_enableResize) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: '最大宽度',
                            hintText: '不限制',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _maxWidth = int.tryParse(v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: '最大高度',
                            hintText: '不限制',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _maxHeight = int.tryParse(v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      title: const Text('保持宽高比'),
                      value: _keepAspectRatio,
                      onChanged: (v) => setState(() => _keepAspectRatio = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Process button
                ElevatedButton.icon(
                  onPressed: hasImage ? () => widget.onProcess(_doProcess) : null,
                  icon: const Icon(Icons.compress),
                  label: const Text('压缩图片'),
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
