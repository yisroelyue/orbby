import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/screen_record_config.dart';
import '../orbby_plugin_screen_record.dart';

/// 闲置面板——负责配置和启动录制。录制开始后创建独立的录制栏浮动窗。
class ScreenRecordScreen extends StatefulWidget {
  const ScreenRecordScreen({super.key});

  @override
  State<ScreenRecordScreen> createState() => _ScreenRecordScreenState();
}

class _ScreenRecordScreenState extends State<ScreenRecordScreen> {
  final _recorder = OrbbyPluginScreenRecord();

  RecordState _recordState = RecordState.idle;
  RecordProgress _progress =
      const RecordProgress(duration: Duration.zero, fileSizeBytes: 0);
  String? _lastOutputPath;
  String _outputDir = '';

  StreamSubscription<RecordState>? _stateSub;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _outputDir = _getDesktopPath();
    _stateSub = _recorder.stateStream.listen((state) {
      if (!mounted) return;
      final prev = _recordState;
      setState(() => _recordState = state);
      if (state == RecordState.recording && prev == RecordState.idle) {
        _startPolling();
      }
      if (state == RecordState.stopping || state == RecordState.idle) {
        _stopPolling();
      }
    });
  }

  String _getDesktopPath() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) return '$userProfile\\Desktop';
    final drv = Platform.environment['HOMEDRIVE'];
    final pth = Platform.environment['HOMEPATH'];
    if (drv != null && pth != null) return '$drv$pth\\Desktop';
    return '.';
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _stopPolling();
    super.dispose();
  }

  // ── Recording bar window ────────────────────────────────────────────

  Future<void> _createRecordingBarWindow() async {
    final view = PlatformDispatcher.instance.views.first;
    final screenSize = view.physicalSize / view.devicePixelRatio;
    const barWidth = 200.0;
    const barHeight = 48.0;

    await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'recording_bar',
          'left': screenSize.width - barWidth - 12,
          'top': 12,
          'width': barWidth,
          'height': barHeight,
        }),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _pickOutputFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择输出文件夹',
    );
    if (result != null && mounted) {
      setState(() => _outputDir = result);
    }
  }

  Future<void> _startRecording() async {
    try {
      final now = DateTime.now();
      final filename =
          'screen_record_${now.year}${_pad(now.month)}${_pad(now.day)}_'
          '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}.mp4';
      final outputPath = '$_outputDir\\$filename';

      final config = ScreenRecordConfig(
        fps: 30,
        bitRate: 5_000_000,
        outputPath: outputPath,
      );
      final result = await _recorder.startRecording(config);
      if (!mounted) return;
      setState(() => _lastOutputPath = result?['outputPath'] as String?);
      await _createRecordingBarWindow();
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? '无法开始录制');
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _startPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _pollProgress(),
    );
  }

  void _stopPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _pollProgress() async {
    if (!mounted) return;
    try {
      final result = await _recorder.getRecordingProgress();
      if (!mounted || result == null) return;
      setState(() {
        _progress = RecordProgress(
          duration: Duration(milliseconds: result['durationMs'] as int? ?? 0),
          fileSizeBytes: result['fileSizeBytes'] as int? ?? 0,
        );
      });
    } catch (_) {}
  }

  Future<void> _openOutputFolder() async {
    if (_lastOutputPath == null) return;
    final dir = File(_lastOutputPath!).parent.path;
    await Process.run('explorer', [dir]);
  }

  Future<void> _stopRecording() async {
    _stopPolling();
    try {
      final result = await _recorder.stopRecording();
      if (!mounted) return;
      final path = result?['outputPath'] as String?;
      final size = result?['fileSizeBytes'] as int? ?? 0;
      setState(() => _lastOutputPath = path);
      if (path != null) {
        _showSnackBar('录制完成: $path (${_formatBytes(size)})');
      }
    } on PlatformException catch (e) {
      _showError(e.message ?? '停止录制失败');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$hh:$mm:$ss';
    return '$mm:$ss';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isRecording = _recordState == RecordState.recording;
    final isPaused = _recordState == RecordState.paused;
    final isActive = isRecording || isPaused;

    return Theme(
      data: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      child: _buildIdlePanel(isActive),
    );
  }

  Widget _buildIdlePanel(bool isActive) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/录制.png',
                  width: 36,
                  height: 36,
                  package: 'orbby_plugin_screen_record',
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.videocam_rounded,
                    size: 36,
                    color: Color(0xFF6750A4),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'orbby屏幕录制',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 录制状态
          if (isActive) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _RecordingDot(),
                  const SizedBox(width: 10),
                  Text(
                    _formatDuration(_progress.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _recordState == RecordState.paused ? '(已暂停)' : '(录制中)',
                    style: TextStyle(
                      color: _recordState == RecordState.paused
                          ? Colors.orangeAccent
                          : Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _stopRecording,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('停止'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            '输出目录',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: !isActive ? _pickOutputFolder : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _outputDir,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '浏览',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 开始按钮
          FilledButton.icon(
            onPressed: isActive ? null : _startRecording,
            icon: Icon(
              isActive ? Icons.fiber_manual_record : Icons.fiber_manual_record,
              size: 20,
            ),
            label: Text(isActive ? '录制中...' : '开始录制'),
            style: FilledButton.styleFrom(
              backgroundColor: isActive ? Colors.grey : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontSize: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            '输出结果',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _lastOutputPath != null
                  ? Row(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 18, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastOutputPath!.split('\\').last,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _openOutputFolder,
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: const Text('打开文件夹',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          '暂无录制文件',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing recording dot ────────────────────────────────────────────

class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
