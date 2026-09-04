import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class WindowsAppIcon {
  static const _channel = MethodChannel('orbby_app_icon');

  /// Returns a PNG icon for an executable, or null if Windows cannot extract it.
  static Future<Uint8List?> fromExecutable(String executablePath) async {
    if (!executablePath.toLowerCase().endsWith('.exe')) return null;
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'extract', executablePath,
    );
    if (raw == null) return null;
    final width = raw['width'] as int;
    final height = raw['height'] as int;
    final rgba = Uint8List.fromList((raw['rgba'] as List).cast<int>());
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }
}
