import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/process_result.dart';
import '../utils/output_utils.dart';

/// Processor for canvas expansion (adding margins around an image).
class CanvasExpander {
  /// Expand canvas by adding margins around the image.
  static Future<ProcessResult> expand({
    required String inputPath,
    required String outputDir,
    int top = 0,
    int bottom = 0,
    int left = 0,
    int right = 0,
    required img.Color color,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    final newWidth = image.width + left + right;
    final newHeight = image.height + top + bottom;

    final expanded = img.Image(width: newWidth, height: newHeight);
    expanded.clear(color);

    img.compositeImage(expanded, image, dstX: left, dstY: top);

    final outputPath = getOutputPath(inputPath, outputDir, '_expanded');
    final outputBytes = img.encodePng(expanded);
    await File(outputPath).writeAsBytes(outputBytes);

    return ProcessResult(
      outputPath: outputPath,
      width: newWidth,
      height: newHeight,
    );
  }
}
