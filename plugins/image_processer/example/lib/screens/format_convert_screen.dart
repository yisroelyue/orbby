import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';
import 'package:path/path.dart' as p;

class FormatConvertScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final String outputDir;
  final void Function(String) onStatusUpdate;
  final Future<void> Function(Future<bool> Function()) onProcess;

  const FormatConvertScreen({
    super.key,
    required this.imagePath,
    required this.imageBytes,
    required this.outputDir,
    required this.onStatusUpdate,
    required this.onProcess,
  });

  @override
  State<FormatConvertScreen> createState() => _FormatConvertScreenState();
}

class _FormatConvertScreenState extends State<FormatConvertScreen> {
  String _targetFormat = 'png';
  int _quality = 90;

  static const _formats = ['png', 'jpeg', 'webp', 'bmp', 'tiff', 'gif', 'ico'];
  static const _alphaUnsupported = ['jpeg', 'bmp', 'gif'];

  bool get _showsAlphaWarning => _alphaUnsupported.contains(_targetFormat);
  bool get _supportsQuality => _targetFormat == 'jpeg' || _targetFormat == 'webp';

  Future<bool> _doProcess() async {
    if (widget.imagePath == null) return false;

    try {
      final result = await ImageProcessor.convertFormat(
        inputPath: widget.imagePath!,
        outputDir: widget.outputDir,
        format: _targetFormat,
        quality: _quality,
      );
      widget.onStatusUpdate(
          '格式转换完成: ${result.width}×${result.height} → ${_targetFormat.toUpperCase()}');
      return true;
    } catch (e) {
      widget.onStatusUpdate('转换失败: $e');
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
                                Text('当前格式: ${p.extension(widget.imagePath!).replaceAll('.', '').toUpperCase()}',
                                    style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Target format
                Text('目标格式', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _formats.map((fmt) {
                    final selected = _targetFormat == fmt;
                    return ChoiceChip(
                      label: Text(fmt.toUpperCase()),
                      selected: selected,
                      onSelected: hasImage ? (v) => setState(() => _targetFormat = fmt) : null,
                    );
                  }).toList(),
                ),

                // Alpha warning
                if (_showsAlphaWarning && hasImage)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_targetFormat.toUpperCase()} 格式不支持透明通道，透明区域将合成为白色背景',
                              style: TextStyle(color: Colors.orange[800], fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // GIF note
                if (_targetFormat == 'gif' && hasImage)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '输出将量化为256色调色板',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),

                if (_supportsQuality) ...[
                  const SizedBox(height: 16),
                  Text('质量: $_quality%', style: theme.textTheme.titleMedium),
                  Slider(
                    value: _quality.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '$_quality%',
                    onChanged: hasImage ? (v) => setState(() => _quality = v.round()) : null,
                  ),
                ],

                const SizedBox(height: 24),

                // Process button
                ElevatedButton.icon(
                  onPressed: hasImage ? () => widget.onProcess(_doProcess) : null,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text('转换为 ${_targetFormat.toUpperCase()}'),
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
