import 'package:image/image.dart' as img;
import 'models/crop_rect.dart';
import 'models/process_result.dart';
import 'utils/output_utils.dart' as output_utils;
import 'processors/crop_rotate_processor.dart';
import 'processors/format_converter.dart';
import 'processors/canvas_expander.dart';
import 'processors/background_filler.dart';
import 'processors/watermark_processor.dart';
import 'processors/compress_processor.dart';

// Re-export models for convenience.
export 'models/crop_rect.dart';
export 'models/process_result.dart';
export 'utils/output_utils.dart';
export 'processors/crop_rotate_processor.dart';
export 'processors/format_converter.dart';
export 'processors/canvas_expander.dart';
export 'processors/background_filler.dart';
export 'processors/watermark_processor.dart';
export 'processors/compress_processor.dart';

/// Core image processing engine for Orbby.
///
/// This class is a facade that delegates to individual processor classes.
/// Each processor is also available directly for more granular imports.
class ImageProcessor {
  /// Crop and rotate an image.
  static Future<ProcessResult> cropRotate({
    required String inputPath,
    required String outputDir,
    required CropRect cropRect,
    double rotation = 0,
    bool flipH = false,
    bool flipV = false,
  }) async {
    return CropRotateProcessor.process(
      inputPath: inputPath,
      outputDir: outputDir,
      cropRect: cropRect,
      rotation: rotation,
      flipH: flipH,
      flipV: flipV,
    );
  }

  /// Convert image format.
  static Future<ProcessResult> convertFormat({
    required String inputPath,
    required String outputDir,
    required String format,
    int quality = 90,
  }) async {
    return FormatConverter.convert(
      inputPath: inputPath,
      outputDir: outputDir,
      format: format,
      quality: quality,
    );
  }

  /// Expand canvas by adding margins around the image.
  static Future<ProcessResult> expandCanvas({
    required String inputPath,
    required String outputDir,
    int top = 0,
    int bottom = 0,
    int left = 0,
    int right = 0,
    required img.Color color,
  }) async {
    return CanvasExpander.expand(
      inputPath: inputPath,
      outputDir: outputDir,
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      color: color,
    );
  }

  /// Fill transparent background with a solid color.
  static Future<ProcessResult> fillBackground({
    required String inputPath,
    required String outputDir,
    required img.Color color,
  }) async {
    return BackgroundFiller.fill(
      inputPath: inputPath,
      outputDir: outputDir,
      color: color,
    );
  }

  /// Add a text watermark to an image.
  static Future<ProcessResult> addTextWatermark({
    required String inputPath,
    required String outputDir,
    required String text,
    double fontSize = 36,
    required img.Color textColor,
    int position = 8,
    double opacity = 0.7,
    int margin = 20,
  }) async {
    return WatermarkProcessor.addText(
      inputPath: inputPath,
      outputDir: outputDir,
      text: text,
      fontSize: fontSize,
      textColor: textColor,
      position: position,
      opacity: opacity,
      margin: margin,
    );
  }

  /// Add an image watermark to an image.
  static Future<ProcessResult> addImageWatermark({
    required String inputPath,
    required String outputDir,
    required String watermarkPath,
    double scale = 0.2,
    int position = 8,
    double opacity = 0.7,
    int margin = 20,
  }) async {
    return WatermarkProcessor.addImage(
      inputPath: inputPath,
      outputDir: outputDir,
      watermarkPath: watermarkPath,
      scale: scale,
      position: position,
      opacity: opacity,
      margin: margin,
    );
  }

  /// Compress an image with specified quality and optional resize.
  static Future<ProcessResult> compress({
    required String inputPath,
    required String outputDir,
    int quality = 80,
    int? maxWidth,
    int? maxHeight,
    bool keepAspectRatio = true,
    String? outputFormat,
  }) async {
    return CompressProcessor.compress(
      inputPath: inputPath,
      outputDir: outputDir,
      quality: quality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      keepAspectRatio: keepAspectRatio,
      outputFormat: outputFormat,
    );
  }

  /// Parse a hex color string (#RRGGBB or #AARRGGBB) to an image Color.
  static img.Color parseHexColor(String hex) {
    return output_utils.parseHexColor(hex);
  }
}
