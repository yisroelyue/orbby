import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/crop_rect.dart';
import '../models/process_result.dart';
import '../utils/output_utils.dart';

/// Processor for crop, rotate, and flip operations.
class CropRotateProcessor {
  /// Crop and rotate an image.
  static Future<ProcessResult> process({
    required String inputPath,
    required String outputDir,
    required CropRect cropRect,
    double rotation = 0,
    bool flipH = false,
    bool flipV = false,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    // Crop
    image = img.copyCrop(
      image,
      x: cropRect.x,
      y: cropRect.y,
      width: cropRect.width,
      height: cropRect.height,
    );

    // Flip
    if (flipH) {
      image = img.flipHorizontal(image);
    }
    if (flipV) {
      image = img.flipVertical(image);
    }

    // Rotate
    if (rotation != 0) {
      image = img.copyRotate(image, angle: rotation);
    }

    final outputPath = getOutputPath(inputPath, outputDir, '_edited');
    final outputBytes = img.encodePng(image);
    await File(outputPath).writeAsBytes(outputBytes);

    return ProcessResult(
      outputPath: outputPath,
      width: image.width,
      height: image.height,
    );
  }
}
