import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter/painting.dart';
import '../models/process_result.dart';
import '../utils/output_utils.dart';

/// Processor for adding text or image watermarks.
class WatermarkProcessor {
  /// Add a text watermark to an image.
  static Future<ProcessResult> addText({
    required String inputPath,
    required String outputDir,
    required String text,
    double fontSize = 36,
    required img.Color textColor,
    int position = 8,
    double opacity = 0.7,
    int margin = 20,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    final textImg = await _createTextImage(text, fontSize, textColor, opacity);

    // Calculate position
    final pos = _getPositionOffset(
      image.width,
      image.height,
      textImg.width,
      textImg.height,
      position,
      margin,
    );

    img.compositeImage(
      image,
      textImg,
      dstX: pos.$1,
      dstY: pos.$2,
      dstW: textImg.width,
      dstH: textImg.height,
    );

    final outputPath = getOutputPath(inputPath, outputDir, '_watermarked');
    final outputBytes = img.encodePng(image);
    await File(outputPath).writeAsBytes(outputBytes);

    return ProcessResult(
      outputPath: outputPath,
      width: image.width,
      height: image.height,
    );
  }

  /// Add an image watermark to an image.
  static Future<ProcessResult> addImage({
    required String inputPath,
    required String outputDir,
    required String watermarkPath,
    double scale = 0.2,
    int position = 8,
    double opacity = 0.7,
    int margin = 20,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    final wmBytes = await File(watermarkPath).readAsBytes();
    img.Image? watermark = img.decodeImage(wmBytes);
    if (watermark == null) throw Exception('Cannot decode watermark image');

    // Scale watermark relative to original image width.
    final safeScale = scale.isFinite ? scale.clamp(0.01, 1.0).toDouble() : 0.2;
    var targetWidth = (image.width * safeScale).round().clamp(1, image.width);
    var targetHeight = (targetWidth * watermark.height / watermark.width)
        .round()
        .clamp(1, image.height);
    if (targetHeight == image.height) {
      targetWidth = (targetHeight * watermark.width / watermark.height)
          .round()
          .clamp(1, image.width);
    }
    watermark = img.copyResize(
      watermark,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );

    watermark = watermark.convert(numChannels: 4);

    // Adjust opacity
    final alpha = (opacity * 255).round();
    for (final pixel in watermark) {
      final currentAlpha = pixel.a.toInt();
      final newAlpha = ((currentAlpha / 255) * alpha).round();
      pixel.a = newAlpha;
    }

    // Calculate position
    final pos = _getPositionOffset(
      image.width,
      image.height,
      watermark.width,
      watermark.height,
      position,
      margin,
    );

    img.compositeImage(
      image,
      watermark,
      dstX: pos.$1,
      dstY: pos.$2,
      dstW: watermark.width,
      dstH: watermark.height,
    );

    final outputPath = getOutputPath(inputPath, outputDir, '_watermarked');
    final outputBytes = img.encodePng(image);
    await File(outputPath).writeAsBytes(outputBytes);

    return ProcessResult(
      outputPath: outputPath,
      width: image.width,
      height: image.height,
    );
  }

  /// Create a text image with Flutter text rendering.
  static Future<img.Image> _createTextImage(
    String text,
    double fontSize,
    img.Color color,
    double opacity,
  ) async {
    if (text.trim().isEmpty) {
      throw Exception('Watermark text is empty');
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _toUiColor(color, opacity),
          fontSize: fontSize.clamp(1, 512).toDouble(),
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final width = math.max(1, textPainter.width.ceil() + 4);
    final height = math.max(1, textPainter.height.ceil() + 4);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    textPainter.paint(canvas, const ui.Offset(2, 2));

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    picture.dispose();

    if (data == null) {
      throw Exception('Cannot render watermark text');
    }

    final decoded = img.decodePng(data.buffer.asUint8List());
    if (decoded == null) {
      throw Exception('Cannot decode rendered watermark text');
    }
    return img.trim(decoded, mode: img.TrimMode.transparent, padding: 1);
  }

  static ui.Color _toUiColor(img.Color color, double opacity) {
    int channel(num value) => (value.clamp(0, 1) * 255).round();
    final alpha = (color.aNormalized * opacity.clamp(0, 1)).clamp(0, 1);
    return ui.Color.fromARGB(
      channel(alpha),
      channel(color.rNormalized),
      channel(color.gNormalized),
      channel(color.bNormalized),
    );
  }

  /// Calculate offset for 9-grid positioning.
  static (int, int) _getPositionOffset(
    int canvasW,
    int canvasH,
    int objW,
    int objH,
    int position,
    int margin,
  ) {
    int x, y;

    switch (position % 3) {
      case 0:
        x = margin;
        break;
      case 1:
        x = (canvasW - objW) ~/ 2;
        break;
      case 2:
        x = canvasW - objW - margin;
        break;
      default:
        x = margin;
    }

    switch (position ~/ 3) {
      case 0:
        y = margin;
        break;
      case 1:
        y = (canvasH - objH) ~/ 2;
        break;
      case 2:
        y = canvasH - objH - margin;
        break;
      default:
        y = margin;
    }

    final maxX = math.max(0, canvasW - objW);
    final maxY = math.max(0, canvasH - objH);
    return (x.clamp(0, maxX), y.clamp(0, maxY));
  }
}
