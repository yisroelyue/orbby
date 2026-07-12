import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/process_result.dart';
import '../utils/output_utils.dart';
import '../utils/image_composite.dart';

/// Processor for filling transparent backgrounds with a solid color.
class BackgroundFiller {
  /// Fill transparent background with a solid color.
  static Future<ProcessResult> fill({
    required String inputPath,
    required String outputDir,
    required img.Color color,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    if (!image.hasAlpha) {
      final outputPath = getOutputPath(inputPath, outputDir, '_filled');
      final outputBytes = img.encodePng(image);
      await File(outputPath).writeAsBytes(outputBytes);
      return ProcessResult(
        outputPath: outputPath,
        width: image.width,
        height: image.height,
      );
    }

    image = compositeOntoColor(image, color);

    final outputPath = getOutputPath(inputPath, outputDir, '_filled');
    final outputBytes = img.encodePng(image);
    await File(outputPath).writeAsBytes(outputBytes);

    return ProcessResult(
      outputPath: outputPath,
      width: image.width,
      height: image.height,
    );
  }
}
