import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orbby/core/sub_app.dart';
import 'package:orbby/core/sub_app_registry.dart';
import 'package:orbby_plugin_screen_record/orbby_plugin_screen_record.dart';
import 'package:window_manager/window_manager.dart';

class ScreenRecordApp extends SubApp {
  @override
  String get id => 'screen_record';

  @override
  String get name => '屏幕录制';

  @override
  String get description => '录制全屏视频，支持暂停/恢复';

  @override
  String get iconAsset => 'assets/png/录制.png';

  @override
  String get packageName => 'orbby';

  @override
  bool get showWindowTitleBar => false;

  @override
  Size get preferredWindowSize => const Size(440, 460);

  @override
  Widget buildApp(BuildContext context) {
    return const _ScreenRecordContent();
  }
}

class _ScreenRecordContent extends StatefulWidget {
  const _ScreenRecordContent();

  @override
  State<_ScreenRecordContent> createState() => _ScreenRecordContentState();
}

class _ScreenRecordContentState extends State<_ScreenRecordContent> {
  final _recorder = OrbbyPluginScreenRecord();

  RecordState _recordState = RecordState.idle;
  Duration _elapsed = Duration.zero;
  String? _lastOutputPath;
  String _outputDir = '';

  StreamSubscription<RecordState>? _stateSub;
  Timer? _progressTimer;

  Rect? _idleRect;

  static const _barWidth = 200.0;
  static const _barHeight = 48.0;
  static const _idleWidth = 440.0;
  static const _idleHeight = 460.0;

  // 深色主题色值
  static const _bg = Color(0xFF1E1E1E);
  static const _card = Color(0xFF2A2A2A);
  static const _textPrimary = Color(0xFFE0E0E0);
  static const _textSecondary = Color(0xFF9E9E9E);
  static const _accent = Color(0xFFB388FF);

  @override
  void initState() {
    super.initState();
    _outputDir = _getDesktopPath();
    _stateSub = _recorder.stateStream.listen(_onStateChanged);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _stopPolling();
    super.dispose();
  }

  void _onStateChanged(RecordState state) {
    if (!mounted) return;
    final prev = _recordState;
    setState(() => _recordState = state);
    if (state == RecordState.recording && prev == RecordState.idle) {
      _enterRecordingMode();
      _startPolling();
    } else if (state == RecordState.stopping && prev != RecordState.idle) {
      _restoreIdleMode();
    } else if (state == RecordState.idle) {
      _stopPolling();
      if (prev != RecordState.stopping) _restoreIdleMode();
    }
  }

  Future<void> _cacheIdleRect() async {
    _idleRect = await windowManager.getBounds();
  }

  Future<void> _enterRecordingMode() async {
    await _cacheIdleRect();
    final view = PlatformDispatcher.instance.views.first;
    final screenSize = view.physicalSize / view.devicePixelRatio;
    await windowManager.setBounds(Rect.fromLTWH(
      screenSize.width - _barWidth - 12, 12, _barWidth, _barHeight,
    ));
    await windowManager.setAlwaysOnTop(true);
  }

  Future<void> _restoreIdleMode() async {
    await windowManager.setAlwaysOnTop(false);
    if (_idleRect != null) {
      await windowManager.setBounds(_idleRect!);
    } else {
      await windowManager.setSize(const Size(_idleWidth, _idleHeight));
      await windowManager.center();
    }
  }

  String _getDesktopPath() {
    final u = Platform.environment['USERPROFILE'];
    if (u != null) return '$u\\Desktop';
    final d = Platform.environment['HOMEDRIVE'];
    final p = Platform.environment['HOMEPATH'];
    if (d != null && p != null) return '$d$p\\Desktop';
    return '.';
  }

  Future<void> _pickOutputFolder() async {
    final r = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择输出文件夹',
    );
    if (r != null && mounted) setState(() => _outputDir = r);
  }

  Future<void> _startRecording() async {
    try {
      final now = DateTime.now();
      final ts =
          '${now.year}${_p(now.month)}${_p(now.day)}_${_p(now.hour)}${_p(now.minute)}${_p(now.second)}';
      final outputPath = '$_outputDir\\screen_record_$ts.mp4';
      final config = ScreenRecordConfig(
        fps: 30, bitRate: 5_000_000, outputPath: outputPath,
      );
      final result = await _recorder.startRecording(config);
      if (!mounted) return;
      setState(() => _lastOutputPath = result?['outputPath'] as String?);
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? '无法开始录制');
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  void _startPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 200), (_) => _pollProgress(),
    );
  }

  void _stopPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _pollProgress() async {
    if (!mounted) return;
    try {
      final r = await _recorder.getRecordingProgress();
      if (!mounted || r == null) return;
      setState(() {
        _elapsed = Duration(milliseconds: r['durationMs'] as int? ?? 0);
      });
    } catch (_) {}
  }

  Future<void> _pauseRecording() async {
    try { await _recorder.pauseRecording(); } catch (_) {}
  }

  Future<void> _resumeRecording() async {
    try { await _recorder.resumeRecording(); } catch (_) {}
  }

  Future<void> _stopRecording() async {
    _stopPolling();
    try {
      final r = await _recorder.stopRecording();
      if (!mounted) return;
      final path = r?['outputPath'] as String?;
      final size = r?['fileSizeBytes'] as int? ?? 0;
      setState(() => _lastOutputPath = path);
      if (path != null) {
        _showSnackBar('录制完成: ${path.split('\\').last} (${_fmtSize(size)})');
      }
    } catch (_) {}
  }

  Future<void> _openOutputFolder() async {
    if (_lastOutputPath == null) return;
    await Process.run('explorer', [File(_lastOutputPath!).parent.path]);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(1)} GB';
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isActive = _recordState == RecordState.recording ||
        _recordState == RecordState.paused ||
        _recordState == RecordState.stopping;

    return Theme(
      data: ThemeData(
        colorSchemeSeed: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: isActive
            ? Container(
                key: const ValueKey('bar'),
                width: double.infinity,
                height: double.infinity,
                color: _bg,
                child: _buildRecordingBar(),
              )
            : Column(
                key: const ValueKey('idle'),
                children: [
                  _buildTitleBar(),
                  Expanded(
                    child: Container(
                      color: _bg,
                      child: _buildIdlePanel(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Title bar ────────────────────────────────────────────────────────

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: Color(0xFF252525),
          border: Border(
            bottom: BorderSide(color: Color(0xFF333333), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Image.asset(
              'assets/录制.png',
              width: 16, height: 16,
              package: 'orbby_plugin_screen_record',
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.videocam_rounded, size: 16, color: _accent),
            ),
            const SizedBox(width: 8),
            const Text('屏幕录制',
                style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            _TitleBarBtn(icon: Icons.minimize_rounded, onTap: () => windowManager.minimize()),
            const SizedBox(width: 4),
            _TitleBarBtn(icon: Icons.close_rounded, onTap: () => windowManager.hide()),
          ],
        ),
      ),
    );
  }

  // ── Idle panel ───────────────────────────────────────────────────────

  Widget _buildIdlePanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('输出目录'),
          const SizedBox(height: 8),
          _buildOutputDirCard(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _startRecording,
            icon: const Icon(Icons.fiber_manual_record, size: 22),
            label: const Text('开始录制'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 28),
          _sectionLabel('输出结果'),
          const SizedBox(height: 8),
          _buildOutputCard(),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textSecondary));
  }

  Widget _buildOutputDirCard() {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickOutputFolder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 22, color: _accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_outputDir,
                    style: const TextStyle(fontSize: 13, color: _textPrimary),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('更改',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _accent)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutputCard() {
    if (_lastOutputPath == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.videocam_off_outlined, size: 28, color: _textSecondary),
              SizedBox(height: 8),
              Text('暂无录制文件',
                  style: TextStyle(fontSize: 13, color: _textSecondary)),
            ],
          ),
        ),
      );
    }

    final filename = _lastOutputPath!.split('\\').last;
    return Material(
      color: const Color(0xFF1B3A2D),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 20, color: Color(0xFF81C784)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(filename,
                  style: const TextStyle(fontSize: 13, color: _textPrimary),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _openOutputFolder,
              icon: const Icon(Icons.folder_open, size: 16, color: Color(0xFF81C784)),
              label: const Text('打开',
                  style: TextStyle(fontSize: 12, color: Color(0xFF81C784))),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recording bar ────────────────────────────────────────────────────

  Widget _buildRecordingBar() {
    final isPaused = _recordState == RecordState.paused;
    final isStopping = _recordState == RecordState.stopping;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (!isPaused && !isStopping)
            _RecordingDot()
          else if (isPaused)
            const Icon(Icons.pause_circle, color: Colors.amber, size: 16)
          else
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
          const SizedBox(width: 8),
          Text(
            _fmtDur(_elapsed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          _BarBtn(
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: isStopping ? null : (isPaused ? _resumeRecording : _pauseRecording),
          ),
          const SizedBox(width: 8),
          _BarBtn(
            icon: Icons.stop_rounded,
            color: Colors.redAccent,
            onTap: isStopping ? null : _stopRecording,
          ),
        ],
      ),
    );
  }
}

// ── Title bar button ──────────────────────────────────────────────────

class _TitleBarBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TitleBarBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white60, size: 16),
      ),
    );
  }
}

// ── Recording bar button ──────────────────────────────────────────────

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _BarBtn({required this.icon, this.color = Colors.white70, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

// ── Recording dot ────────────────────────────────────────────────────

class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.2, end: 1.0).animate(_c),
      child: Container(
        width: 12, height: 12,
        decoration: const BoxDecoration(
          color: Color(0xFFFF3B30), shape: BoxShape.circle,
        ),
      ),
    );
  }
}

void registerScreenRecordApp() {
  SubAppRegistry.register(() => ScreenRecordApp());
}
