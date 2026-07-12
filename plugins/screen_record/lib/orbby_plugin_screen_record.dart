import 'models/screen_record_config.dart';
import 'orbby_plugin_screen_record_platform_interface.dart';

export 'models/screen_record_config.dart';
export 'src/screen_record_screen.dart';
export 'src/recording_bar_screen.dart';

/// The main class for screen recording functionality.
///
/// Provides a cross-platform API for screen recording. Currently supports
/// Windows via DXGI Desktop Duplication and Media Foundation encoding.
///
/// Usage:
/// ```dart
/// final recorder = OrbbyPluginScreenRecord();
///
/// // Check support
/// if (await recorder.isSupported()) {
///   // Start recording
///   final result = await recorder.startRecording(
///     const ScreenRecordConfig(fps: 30, bitRate: 5_000_000),
///   );
///   final outputPath = result['outputPath'];
///
///   // Listen to state changes
///   recorder.stateStream.listen((state) {
///     print('Recording state: $state');
///   });
///
///   // Listen to progress
///   recorder.progressStream.listen((progress) {
///     print('Duration: ${progress.duration}');
///   });
///
///   // Stop recording
///   await recorder.stopRecording();
/// }
/// ```
class OrbbyPluginScreenRecord {
  /// Returns the platform version string.
  Future<String?> getPlatformVersion() {
    return OrbbyPluginScreenRecordPlatform.instance.getPlatformVersion();
  }

  /// Returns whether screen recording is supported on the current platform.
  ///
  /// On Windows, this requires Windows 8 or later with DXGI support.
  Future<bool> isSupported() {
    return OrbbyPluginScreenRecordPlatform.instance.isSupported();
  }

  /// Starts recording the full screen with the given [config].
  ///
  /// The returned map contains:
  /// - `outputPath` (String): Path to the output video file.
  ///
  /// Throws a [PlatformException] if:
  /// - Screen recording is already in progress.
  /// - The platform does not support recording.
  /// - Failed to initialize the capture or encoding pipeline.
  Future<Map<String, dynamic>?> startRecording(
      ScreenRecordConfig config) async {
    return OrbbyPluginScreenRecordPlatform.instance
        .startRecording(config.toMap());
  }

  /// Pauses the active recording.
  ///
  /// Frame capture is suspended but the output file remains open.
  /// Call [resumeRecording] to continue.
  ///
  /// Throws a [PlatformException] if no recording is in progress.
  Future<void> pauseRecording() async {
    return OrbbyPluginScreenRecordPlatform.instance.pauseRecording();
  }

  /// Resumes a paused recording.
  ///
  /// Frame capture resumes from where it was paused.
  ///
  /// Throws a [PlatformException] if recording is not paused.
  Future<void> resumeRecording() async {
    return OrbbyPluginScreenRecordPlatform.instance.resumeRecording();
  }

  /// Stops the recording and finalizes the output file.
  ///
  /// The returned map contains:
  /// - `outputPath` (String): Path to the finalized video file.
  /// - `fileSizeBytes` (int): Size of the output file in bytes.
  ///
  /// Throws a [PlatformException] if no recording is in progress.
  Future<Map<String, dynamic>?> stopRecording() async {
    return OrbbyPluginScreenRecordPlatform.instance.stopRecording();
  }

  /// Polls the current recording progress.
  ///
  /// Returns a map with "durationMs" and "fileSizeBytes", or null if not
  /// recording. Useful for periodic polling from a Dart timer to update
  /// the UI during recording.
  Future<Map<String, dynamic>?> getRecordingProgress() async {
    return OrbbyPluginScreenRecordPlatform.instance
        .getRecordingProgress();
  }

  /// Stream that emits the current recording state.
  ///
  /// Possible values: [RecordState.idle], [RecordState.recording],
  /// [RecordState.paused], [RecordState.stopping].
  Stream<RecordState> get stateStream {
    return OrbbyPluginScreenRecordPlatform.instance.onRecordingStateChanged
        .map((stateStr) {
      switch (stateStr) {
        case 'recording':
          return RecordState.recording;
        case 'paused':
          return RecordState.paused;
        case 'stopping':
          return RecordState.stopping;
        default:
          return RecordState.idle;
      }
    });
  }

  /// Stream that emits recording progress updates.
  ///
  /// Each event contains the current recording duration and output file size.
  Stream<RecordProgress> get progressStream {
    return OrbbyPluginScreenRecordPlatform.instance.onRecordingProgress
        .map((map) => RecordProgress(
              duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
              fileSizeBytes: map['fileSizeBytes'] as int? ?? 0,
            ));
  }
}
