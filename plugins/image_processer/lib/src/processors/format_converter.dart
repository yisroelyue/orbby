import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/process_result.dart';
import '../utils/output_utils.dart';
import '../utils/image_composite.dart';

/// Processor for image format conversion.
class FormatConverter {
  /// Convert image to the target format.
  static Future<ProcessResult> convert({
    required String inputPath,
    required String outputDir,
    required String format,
    int quality = 90,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    final ext = format.toLowerCase();
    Uint8List outputBytes;

    switch (ext) {
      case 'png':
        outputBytes = img.encodePng(image);
        break;
      case 'jpeg':
      case 'jpg':
        if (image.hasAlpha) {
          image = compositeOntoWhite(image);
        }
        outputBytes = img.encodeJpg(image, quality: quality);
        break;
      case 'webp':
        outputBytes = img.encodeWebP(image);
        break;
      case 'bmp':
        if (image.hasAlpha) {
          image = compositeOntoWhite(image);
        }
        outputBytes = img.encodeBmp(image);
        break;
      case 'tiff':
        outputBytes = img.encodeTiff(image);
        break;
      case 'gif':
        if (image.hasAlpha) {
          image = compositeOntoWhite(image);
        }
        image = img.quantize(image, numberOfColors: 256);
        outputBytes = img.encodeGif(image);
        break;
      case 'ico':
        outputBytes = img.encodeIco(image);
        break;
      default:
        throw Exception('Unsupported format: $format');
    }

    final outputPath = getOutputPath(inputPath, outputDir, '_converted', ext);
    await File(outputPath).writeAsBytes(outputBytes);

    return ProcessResult(
      outputPath: outputPath,
      width: image.width,
      height: image.height,
    );
  }
}
