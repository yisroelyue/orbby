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

void main() {
  runApp(const OrbbyApp());
}

class OrbbyApp extends StatelessWidget {
  const OrbbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbby 图像处理器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _imagePath;
  String? _imageName;
  String _outputDir = '';
  String _statusMessage = '请选择图片文件';
  bool _isProcessing = false;
  ui.Image? _loadedImage;
  Uint8List? _imageBytes;

  final List<String> _featureNames = [
    '裁剪旋转',
    '格式转换',
    '扩图',
    '背景填充',
    '水印',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _featureNames.length, vsync: this);
    _outputDir = p.join(
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '',
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
      _statusMessage = '已加载: ${file.name} (${_formatSize(file.size)})';
    });

    // Load image bytes for preview and get dimensions
    final bytes = await File(file.path!).readAsBytes();
    _imageBytes = bytes;

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _loadedImage?.dispose();
    _loadedImage = frame.image;

    setState(() {
      _statusMessage = '已加载: ${file.name} | ${_loadedImage!.width}×${_loadedImage!.height} | ${_formatSize(file.size)}';
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
    setState(() {
      _statusMessage = message;
    });
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

    // Ensure dialog shows for at least 1 second
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
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: success ? Colors.white : null,
                  ),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: success ? Colors.green[600] : null,
          duration: Duration(seconds: success ? 5 : 3),
          dismissDirection: DismissDirection.horizontal,
        ),
      );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orbby 图像处理器'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Top toolbar
          _buildToolbar(),
          // Tab bar
          TabBar(
            controller: _tabController,
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            tabs: _featureNames.map((name) => Tab(text: name)).toList(),
          ),
          // Feature content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                CropRotateScreen(
                  imagePath: _imagePath,
                  imageBytes: _imageBytes,
                  loadedImage: _loadedImage,
                  outputDir: _outputDir,
                  onStatusUpdate: _updateStatus,
                  onProcess: _processWithDialog,
                ),
                FormatConvertScreen(
                  imagePath: _imagePath,
                  imageBytes: _imageBytes,
                  outputDir: _outputDir,
                  onStatusUpdate: _updateStatus,
                  onProcess: _processWithDialog,
                ),
                CanvasExpandScreen(
                  imagePath: _imagePath,
                  imageBytes: _imageBytes,
                  loadedImage: _loadedImage,
                  outputDir: _outputDir,
                  onStatusUpdate: _updateStatus,
                  onProcess: _processWithDialog,
                ),
                BackgroundFillScreen(
                  imagePath: _imagePath,
                  imageBytes: _imageBytes,
                  loadedImage: _loadedImage,
                  outputDir: _outputDir,
                  onStatusUpdate: _updateStatus,
                  onProcess: _processWithDialog,
                ),
                WatermarkScreen(
                  imagePath: _imagePath,
                  imageBytes: _imageBytes,
                  loadedImage: _loadedImage,
                  outputDir: _outputDir,
                  onStatusUpdate: _updateStatus,
                  onProcess: _processWithDialog,
                ),
              ],
            ),
          ),
        ],
      ),
      // Status bar
      bottomNavigationBar: _buildStatusBar(),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _pickImage,
            icon: const Icon(Icons.image),
            label: const Text('选择图片'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : _pickOutputDir,
            icon: const Icon(Icons.folder),
            label: Text(
              '输出: ${p.basename(_outputDir)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (_imageName != null)
            Flexible(
              child: Text(
                _imageName!,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (_isProcessing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_isProcessing) const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
