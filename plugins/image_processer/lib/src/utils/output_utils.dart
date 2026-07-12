import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Generate output path with suffix, avoiding overwrites.
String getOutputPath(String inputPath, String outputDir, String suffix, [String? ext]) {
  final baseName = p.basenameWithoutExtension(inputPath);
  final extension = ext ?? p.extension(inputPath).replaceAll('.', '');
  final fileName = '$baseName$suffix.$extension';
  var outputPath = p.join(outputDir, fileName);

  if (!File(outputPath).existsSync()) return outputPath;

  for (int i = 1; i < 1000; i++) {
    final newName = '$baseName${suffix}_$i.$extension';
    outputPath = p.join(outputDir, newName);
    if (!File(outputPath).existsSync()) return outputPath;
  }

  return outputPath;
}

/// Parse a hex color string (#RRGGBB or #AARRGGBB) to an image Color.
img.Color parseHexColor(String hex) {
  hex = hex.replaceAll('#', '');
  if (hex.length == 6) {
    hex = 'FF$hex';
  }
  final value = int.parse(hex, radix: 16);
  return img.ColorUint8.rgba(
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
    (value >> 24) & 0xFF,
  );
}
