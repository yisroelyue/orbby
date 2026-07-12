import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'orbby_plugin_image_processer_platform_interface.dart';

/// An implementation of [OrbbyPluginImageProcesserPlatform] that uses method channels.
class MethodChannelOrbbyPluginImageProcesser extends OrbbyPluginImageProcesserPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('orbby_plugin_image_processer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
