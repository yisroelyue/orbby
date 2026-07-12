import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'screens/crop_rotate_screen.dart';
import 'screens/format_convert_screen.dart';
import 'screens/canvas_expand_screen.dart';
import 'screens/background_fill_screen.dart';
import 'screens/watermark_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _imagePath;
  String? _imageName;
  String _outputDir = '';
  String _statusMessage = '请选择图片文件';
  bool _isProcessing = false;
  ui.Image? _loadedImage;
  Uint8List? _imageBytes;

  final List<String> _featureNames = [
    '裁剪旋转', '格式转换', '扩图', '背景填充', '水印',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _featureNames.length, vsync: this);
    _outputDir = p.join(
      Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '',
      'Desktop',
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loadedImage?.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    setState(() {
      _imagePath = file.path;
      _imageName = file.name;
    });

    final bytes = await File(file.path!).readAsBytes();
    _imageBytes = bytes;

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _loadedImage?.dispose();
    _loadedImage = frame.image;

    setState(() {
      _statusMessage =
          '已加载: ${file.name} | ${_loadedImage!.width}×${_loadedImage!.height}'
          ' | ${_formatSize(file.size)}';
    });
  }

  Future<void> _pickOutputDir() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _outputDir = result;
        _statusMessage = '输出目录: $result';
      });
    }
  }

  void _updateStatus(String message) {
    setState(() => _statusMessage = message);
  }

  Future<void> _processWithDialog(Future<bool> Function() processFn) async {
    if (_imagePath == null) {
      _showSnackBar('请先选择图片');
      return;
    }

    setState(() => _isProcessing = true);
    final startTime = DateTime.now();

    bool success = false;
    String? error;
    try {
      success = await processFn();
    } catch (e) {
      error = e.toString();
    }

    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(const Duration(seconds: 1) - elapsed);
    }

    if (mounted) {
      setState(() => _isProcessing = false);
      if (success) {
        _updateStatus('处理完成！');
        _showSnackBar('处理完成！文件已保存到输出目录', success: true);
      } else {
        _updateStatus('处理失败: ${error ?? "未知错误"}');
        _showSnackBar('处理失败: ${error ?? "未知错误"}');
      }
    }
  }

  void _showSnackBar(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.info,
                color: success ? Colors.white : null,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: success ? Colors.green.shade700 : null,
          duration: Duration(seconds: success ? 4 : 2),
          dismissDirection: DismissDirection.horizontal,
        ),
      );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Column(
        children: [
          _buildToolbar(cs),
          _buildTabBar(cs),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                CropRotateScreen(imagePath: _imagePath, imageBytes: _imageBytes, loadedImage: _loadedImage, outputDir: _outputDir, onStatusUpdate: _updateStatus, onProcess: _processWithDialog),
                FormatConvertScreen(imagePath: _imagePath, imageBytes: _imageBytes, outputDir: _outputDir, onStatusUpdate: _updateStatus, onProcess: _processWithDialog),
                CanvasExpandScreen(imagePath: _imagePath, imageBytes: _imageBytes, loadedImage: _loadedImage, outputDir: _outputDir, onStatusUpdate: _updateStatus, onProcess: _processWithDialog),
                BackgroundFillScreen(imagePath: _imagePath, imageBytes: _imageBytes, loadedImage: _loadedImage, outputDir: _outputDir, onStatusUpdate: _updateStatus, onProcess: _processWithDialog),
                WatermarkScreen(imagePath: _imagePath, imageBytes: _imageBytes, loadedImage: _loadedImage, outputDir: _outputDir, onStatusUpdate: _updateStatus, onProcess: _processWithDialog),
              ],
            ),
          ),
          _buildStatusBar(cs),
        ],
      ),
    );
  }

  // ── Toolbar ──────────────────────────────────────────────────────────

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(
          bottom: BorderSide(color: Color(0xFF333333), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _ToolBtn(icon: Icons.image_outlined, label: '选择图片', color: cs.primary, onTap: _isProcessing ? null : _pickImage),
          const SizedBox(width: 10),
          _ToolBtn(icon: Icons.folder_outlined, label: '输出目录', onTap: _isProcessing ? null : _pickOutputDir),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_outputDir,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          if (_imageName != null) ...[
            const SizedBox(width: 12),
            const Icon(Icons.image, size: 16, color: Color(0xFF757575)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(_imageName!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE0E0E0))),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab bar ──────────────────────────────────────────────────────────

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      color: const Color(0xFF252525),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        tabAlignment: TabAlignment.fill,
        indicatorColor: cs.primary,
        indicatorWeight: 2.5,
        dividerHeight: 0,
        labelColor: cs.primary,
        unselectedLabelColor: const Color(0xFF9E9E9E),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        indicatorSize: TabBarIndicatorSize.label,
        tabs: _featureNames.map((name) => Tab(text: name)).toList(),
      ),
    );
  }

  // ── Status bar ───────────────────────────────────────────────────────

  Widget _buildStatusBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(
          top: BorderSide(color: Color(0xFF333333), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (_isProcessing) ...[
            const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(_statusMessage,
                style: const TextStyle(fontSize: 12, color: Color(0xFFE0E0E0)),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ── Toolbar button ────────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const _ToolBtn({required this.icon, required this.label, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final c = color ?? const Color(0xFFE0E0E0);
    return Material(
      color: active ? c.withAlpha(25) : const Color(0xFF333333),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? c : const Color(0xFF757575)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: active ? c : const Color(0xFF757575))),
            ],
          ),
        ),
      ),
    );
  }
}
