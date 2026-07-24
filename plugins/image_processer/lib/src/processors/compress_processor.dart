import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/process_result.dart';
import '../utils/output_utils.dart';
import '../utils/image_composite.dart';

/// Processor for image compression.
class CompressProcessor {
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
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    // Resize if needed
    if (maxWidth != null || maxHeight != null) {
      image = _resizeImage(image, maxWidth, maxHeight, keepAspectRatio);
    }

    // Determine output format
    final format = outputFormat ?? _detectFormat(inputPath);

    // Encode with compression
    Uint8List outputBytes;
    switch (format.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        if (image.hasAlpha) {
          image = compositeOntoWhite(image);
        }
        outputBytes = img.encodeJpg(image, quality: quality);
        break;
      case 'webp':
        outputBytes = img.encodeWebP(image);
        break;
      case 'png':
        // PNG is lossless, but we can reduce colors for compression
        outputBytes = img.encodePng(image);
        break;
      default:
        // Default to JPEG for best compression
        if (image.hasAlpha) {
          image = compositeOntoWhite(image);
        }
        outputBytes = img.encodeJpg(image, quality: quality);
    }

    final outputPath = getOutputPath(inputPath, outputDir, '_compressed', format);
    await File(outputPath).writeAsBytes(outputBytes);

    return ProcessResult(
      outputPath: outputPath,
      width: image.width,
      height: image.height,
    );
  }

  /// Resize image while optionally maintaining aspect ratio.
  static img.Image _resizeImage(
    img.Image image,
    int? maxWidth,
    int? maxHeight,
    bool keepAspectRatio,
  ) {
    if (!keepAspectRatio) {
      return img.copyResize(
        image,
        width: maxWidth ?? image.width,
        height: maxHeight ?? image.height,
        interpolation: img.Interpolation.linear,
      );
    }

    // Calculate new dimensions maintaining aspect ratio
    double ratio = 1.0;
    if (maxWidth != null && image.width > maxWidth) {
      ratio = maxWidth / image.width;
    }
    if (maxHeight != null && image.height > maxHeight) {
      final heightRatio = maxHeight / image.height;
      if (heightRatio < ratio) ratio = heightRatio;
    }

    if (ratio >= 1.0) return image;

    return img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  /// Detect format from file extension.
  static String _detectFormat(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (['jpg', 'jpeg'].contains(ext)) return 'jpg';
    if (ext == 'webp') return 'webp';
    if (ext == 'png') return 'png';
    return 'jpg'; // Default to JPEG for best compression
  }

  /// Get original file size in bytes.
  static Future<int> getOriginalSize(String path) async {
    final file = File(path);
    return file.length();
  }

  /// Calculate compression ratio.
  static double getCompressionRatio(int originalSize, int compressedSize) {
    if (originalSize == 0) return 0;
    return (1 - compressedSize / originalSize) * 100;
  }
}
