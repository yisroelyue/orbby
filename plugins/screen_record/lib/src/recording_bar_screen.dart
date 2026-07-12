import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/screen_record_config.dart';
import '../orbby_plugin_screen_record.dart';

/// 独立录制栏窗口——作为单独的浮动窗运行，不依赖父窗口状态。
class RecordingBarScreen extends StatefulWidget {
  const RecordingBarScreen({super.key});

  @override
  State<RecordingBarScreen> createState() => _RecordingBarScreenState();
}

class _RecordingBarScreenState extends State<RecordingBarScreen> {
  final _recorder = OrbbyPluginScreenRecord();

  RecordState _recordState = RecordState.recording;
  Duration _elapsed = Duration.zero;

  StreamSubscription<RecordState>? _stateSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _stateSub = _recorder.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _recordState = s);
      if (s == RecordState.idle || s == RecordState.stopping) {
        _stopPolling();
      }
      if (s == RecordState.idle) {
        // 录制结束，关闭自身
        windowManager.hide();
      }
    });
    _startPolling();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (_recordState != RecordState.recording) return;
      try {
        final p = await _recorder.getRecordingProgress();
        if (p != null && mounted) {
          setState(() => _elapsed = Duration(
                milliseconds: p['durationMs'] as int? ?? 0,
              ));
        }
      } catch (_) {}
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pause() async {
    try {
      await _recorder.pauseRecording();
    } catch (_) {}
  }

  Future<void> _resume() async {
    try {
      await _recorder.resumeRecording();
    } catch (_) {}
  }

  Future<void> _stop() async {
    try {
      await _recorder.stopRecording();
    } catch (_) {}
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isPaused = _recordState == RecordState.paused;
    final isStopping = _recordState == RecordState.stopping;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSansSC'),
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        body: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
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
              Text(
                _fmt(_elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              _Btn(
                icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: isPaused ? Colors.greenAccent : Colors.orangeAccent,
                onTap: isStopping ? null : (isPaused ? _resume : _pause),
              ),
              const SizedBox(width: 2),
              _Btn(
                icon: Icons.stop_rounded,
                color: Colors.redAccent,
                onTap: isStopping ? null : _stop,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _Btn({required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(40),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

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
      duration: const Duration(milliseconds: 800),
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
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_c),
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
