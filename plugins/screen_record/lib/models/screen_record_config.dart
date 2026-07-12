/// Configuration for screen recording.
class ScreenRecordConfig {
  /// Output video width in pixels. Set to 0 to use the screen's native width.
  final int width;

  /// Output video height in pixels. Set to 0 to use the screen's native height.
  final int height;

  /// Frames per second for the recording.
  final int fps;

  /// Video bitrate in bits per second (e.g., 5_000_000 for 5 Mbps).
  final int bitRate;

  /// Output file format. Currently only "mp4" is supported on Windows.
  final String format;

  /// Output file path. If null, a timestamped file will be created in the
  /// user's Videos folder.
  final String? outputPath;

  const ScreenRecordConfig({
    this.width = 0,
    this.height = 0,
    this.fps = 30,
    this.bitRate = 5_000_000,
    this.format = 'mp4',
    this.outputPath,
  });

  /// Creates a [Map] from this config suitable for passing over the method
  /// channel.
  Map<String, dynamic> toMap() {
    return {
      'width': width,
      'height': height,
      'fps': fps,
      'bitRate': bitRate,
      'format': format,
      'outputPath': outputPath,
    };
  }
}

/// Represents the current state of the screen recorder.
enum RecordState {
  /// Not recording.
  idle,

  /// Actively capturing and encoding frames.
  recording,

  /// Recording is temporarily paused.
  paused,

  /// Recording is in the process of stopping and finalizing the output file.
  stopping,
}

/// Progress information emitted during recording.
class RecordProgress {
  /// The elapsed recording duration.
  final Duration duration;

  /// The current size of the output file in bytes.
  final int fileSizeBytes;

  const RecordProgress({
    required this.duration,
    required this.fileSizeBytes,
  });
}
