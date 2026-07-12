import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'orbby_plugin_image_processer_method_channel.dart';

abstract class OrbbyPluginImageProcesserPlatform extends PlatformInterface {
  /// Constructs a OrbbyPluginImageProcesserPlatform.
  OrbbyPluginImageProcesserPlatform() : super(token: _token);

  static final Object _token = Object();

  static OrbbyPluginImageProcesserPlatform _instance = MethodChannelOrbbyPluginImageProcesser();

  /// The default instance of [OrbbyPluginImageProcesserPlatform] to use.
  ///
  /// Defaults to [MethodChannelOrbbyPluginImageProcesser].
  static OrbbyPluginImageProcesserPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [OrbbyPluginImageProcesserPlatform] when
  /// they register themselves.
  static set instance(OrbbyPluginImageProcesserPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
