/// Result of an image processing operation.
class ProcessResult {
  final String outputPath;
  final int width;
  final int height;

  ProcessResult({
    required this.outputPath,
    required this.width,
    required this.height,
  });
}
