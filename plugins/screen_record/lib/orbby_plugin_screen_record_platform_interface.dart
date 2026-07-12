import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'orbby_plugin_screen_record_method_channel.dart';

abstract class OrbbyPluginScreenRecordPlatform extends PlatformInterface {
  /// Constructs a OrbbyPluginScreenRecordPlatform.
  OrbbyPluginScreenRecordPlatform() : super(token: _token);

  static final Object _token = Object();

  static OrbbyPluginScreenRecordPlatform _instance =
      MethodChannelOrbbyPluginScreenRecord();

  /// The default instance of [OrbbyPluginScreenRecordPlatform] to use.
  ///
  /// Defaults to [MethodChannelOrbbyPluginScreenRecord].
  static OrbbyPluginScreenRecordPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [OrbbyPluginScreenRecordPlatform]
  /// when they register themselves.
  static set instance(OrbbyPluginScreenRecordPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns the platform version string.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Returns whether screen recording is supported on this platform.
  Future<bool> isSupported() {
    throw UnimplementedError('isSupported() has not been implemented.');
  }

  /// Starts screen recording with the given [config].
  ///
  /// Returns a map containing the output file path and other metadata.
  /// Throws a [PlatformException] if recording fails to start.
  Future<Map<String, dynamic>?> startRecording(
      Map<String, dynamic> config) {
    throw UnimplementedError('startRecording() has not been implemented.');
  }

  /// Pauses the active recording. No frames will be captured until
  /// [resumeRecording] is called.
  Future<void> pauseRecording() {
    throw UnimplementedError('pauseRecording() has not been implemented.');
  }

  /// Resumes a paused recording.
  Future<void> resumeRecording() {
    throw UnimplementedError('resumeRecording() has not been implemented.');
  }

  /// Stops the active recording and finalizes the output file.
  ///
  /// Returns a map containing the output file path and final file size.
  Future<Map<String, dynamic>?> stopRecording() {
    throw UnimplementedError('stopRecording() has not been implemented.');
  }

  /// Polls the current recording progress.
  ///
  /// Returns a map with keys: "durationMs" (int) and "fileSizeBytes" (int).
  /// Returns null if no recording is in progress.
  Future<Map<String, dynamic>?> getRecordingProgress() {
    throw UnimplementedError(
        'getRecordingProgress() has not been implemented.');
  }

  /// Stream of recording state changes.
  /// Emits values: "idle", "recording", "paused", "stopping".
  Stream<String> get onRecordingStateChanged {
    throw UnimplementedError(
        'onRecordingStateChanged has not been implemented.');
  }

  /// Stream of recording progress updates.
  /// Emits maps with keys: "durationMs" (int) and "fileSizeBytes" (int).
  Stream<Map<String, dynamic>> get onRecordingProgress {
    throw UnimplementedError(
        'onRecordingProgress has not been implemented.');
  }
}
