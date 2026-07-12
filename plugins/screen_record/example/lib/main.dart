import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orbby_plugin_screen_record/orbby_plugin_screen_record.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Always frameless — avoids flicker from title-bar style transitions.
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  await windowManager.setMinimumSize(const Size(280, 48));
  await windowManager.setSize(const Size(440, 420));
  await windowManager.center();
  await windowManager.setTitle('orbby屏幕录制');

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _recorder = OrbbyPluginScreenRecord();

  RecordState _recordState = RecordState.idle;
  RecordProgress _progress = const RecordProgress(
    duration: Duration.zero,
    fileSizeBytes: 0,
  );
  String? _lastOutputPath;
  String _outputDir = '';

  StreamSubscription<RecordState>? _stateSubscription;
  Timer? _progressTimer;

  // Cached idle window geometry so we can restore on stop.
  Rect? _idleRect;

  @override
  void initState() {
    super.initState();
    _outputDir = _getDesktopPath();
    _initStateStream();
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
    _stateSubscription?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _initStateStream() {
    _stateSubscription = _recorder.stateStream.listen((state) {
      if (!mounted) return;
      final prevState = _recordState;
      setState(() => _recordState = state);
      _onStateChanged(state, prevState);
    });
  }

  // ── Window geometry management ──────────────────────────────────────

  Future<void> _cacheIdleRect() async {
    _idleRect = await windowManager.getBounds();
  }

  Future<void> _enterRecordingMode() async {
    await _cacheIdleRect();
    // Get screen size from the platform dispatcher.
    final view = PlatformDispatcher.instance.views.first;
    final screenSize = view.physicalSize / view.devicePixelRatio;
    // Shrink to a compact floating bar pinned to top-right.
    const barWidth = 200.0;
    const barHeight = 48.0;
    await windowManager.setBounds(
      Rect.fromLTWH(screenSize.width - barWidth - 12, 12, barWidth, barHeight),
    );
    await windowManager.setAlwaysOnTop(true);
  }

  Future<void> _restoreIdleMode() async {
    await windowManager.setAlwaysOnTop(false);
    if (_idleRect != null) {
      await windowManager.setBounds(_idleRect!);
    } else {
      await windowManager.setSize(const Size(440, 420));
      await windowManager.center();
    }
    await windowManager.setTitle('orbby屏幕录制');
  }

  void _onStateChanged(RecordState state, RecordState prevState) {
    if (state == RecordState.recording && prevState == RecordState.idle) {
      _enterRecordingMode();
    } else if (state == RecordState.stopping && prevState != RecordState.idle) {
      // Restore main window immediately — don't wait for Finalize.
      _restoreIdleMode();
    } else if (state == RecordState.idle) {
      // Ensure we're back in idle mode (no-op if already restored).
      if (prevState != RecordState.stopping) {
        _restoreIdleMode();
      }
    }
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
      setState(() {
        _lastOutputPath = result?['outputPath'] as String?;
      });
      _progressTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _pollProgress(),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? '无法开始录制');
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Future<void> _pollProgress() async {
    if (!mounted) return;
    try {
      final result = await _recorder.getRecordingProgress();
      if (!mounted || result == null) return;
      setState(() {
        _progress = RecordProgress(
          duration:
              Duration(milliseconds: result['durationMs'] as int? ?? 0),
          fileSizeBytes: result['fileSizeBytes'] as int? ?? 0,
        );
      });
    } catch (_) {}
  }

  Future<void> _pauseRecording() async {
    try {
      await _recorder.pauseRecording();
    } on PlatformException catch (e) {
      _showError(e.message ?? '暂停失败');
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _recorder.resumeRecording();
    } on PlatformException catch (e) {
      _showError(e.message ?? '继续失败');
    }
  }

  Future<void> _openOutputFolder() async {
    if (_lastOutputPath == null) return;
    final dir = File(_lastOutputPath!).parent.path;
    await Process.run('explorer', [dir]);
  }

  Future<void> _stopRecording() async {
    _progressTimer?.cancel();
    _progressTimer = null;
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
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showSnackBar(String message) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
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
    // Show recording bar only when actively recording or paused.
    // When stopping, the main window has already been restored.
    final isActive = isRecording || isPaused;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor:
            isActive ? const Color(0xFF1E1E1E) : null,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey(isActive ? 'bar' : 'idle'),
            child: isActive ? _buildRecordingBar() : _buildIdlePanel(),
          ),
        ),
      ),
    );
  }

  // ── Idle panel (shown before recording starts) ─────────────────────

  Widget _buildIdlePanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // App icon + title.
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
                  errorBuilder: (_, __, ___) => const Icon(
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

          // Output directory label.
          Text(
            '输出目录',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),

          // Output folder selector.
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap:
                  _recordState == RecordState.idle ? _pickOutputFolder : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

          // Start button (green).
          FilledButton.icon(
            onPressed: _startRecording,
            icon: const Icon(Icons.fiber_manual_record, size: 20),
            label: const Text('开始录制'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontSize: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Output result (always visible).
          Text(
            '输出结果',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recording bar (floating top-right overlay) ──────────────────────

  Widget _buildRecordingBar() {
    final isPaused = _recordState == RecordState.paused;
    final isStopping = _recordState == RecordState.stopping;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Recording dot / status icon.
          if (!isPaused && !isStopping)
            _RecordingDot()
          else if (isPaused)
            const Icon(Icons.pause_circle, color: Colors.orange, size: 14)
          else
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),

          const SizedBox(width: 6),

          // Duration.
          Text(
            _formatDuration(_progress.duration),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),

          const Spacer(),

          // Pause / Resume.
          _CompactButton(
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            color: isPaused ? Colors.greenAccent : Colors.orangeAccent,
            onPressed: isStopping
                ? null
                : (isPaused ? _resumeRecording : _pauseRecording),
          ),

          const SizedBox(width: 2),

          // Stop.
          _CompactButton(
            icon: Icons.stop_rounded,
            color: Colors.redAccent,
            onPressed: isStopping ? null : _stopRecording,
          ),
        ],
      ),
    );
  }
}

// ── Reusable compact button for the recording bar ────────────────────

class _CompactButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _CompactButton({
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(40),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 20),
        ),
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
