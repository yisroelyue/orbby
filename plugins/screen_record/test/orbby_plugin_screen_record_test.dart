import 'package:flutter_test/flutter_test.dart';
import 'package:orbby_plugin_screen_record/orbby_plugin_screen_record.dart';
import 'package:orbby_plugin_screen_record/orbby_plugin_screen_record_platform_interface.dart';
import 'package:orbby_plugin_screen_record/orbby_plugin_screen_record_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockOrbbyPluginScreenRecordPlatform
    with MockPlatformInterfaceMixin
    implements OrbbyPluginScreenRecordPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> isSupported() => Future.value(true);

  @override
  Future<Map<String, dynamic>?> startRecording(
          Map<String, dynamic> config) async =>
      {'outputPath': '/test/output.mp4'};

  @override
  Future<void> pauseRecording() async {}

  @override
  Future<void> resumeRecording() async {}

  @override
  Future<Map<String, dynamic>?> stopRecording() async =>
      {'outputPath': '/test/output.mp4', 'fileSizeBytes': 12345};

  @override
  Future<Map<String, dynamic>?> getRecordingProgress() async =>
      {'durationMs': 5000, 'fileSizeBytes': 10000};

  @override
  Stream<String> get onRecordingStateChanged =>
      Stream.value('idle');

  @override
  Stream<Map<String, dynamic>> get onRecordingProgress =>
      Stream.value({'durationMs': 0, 'fileSizeBytes': 0});
}

void main() {
  final initialPlatform =
      OrbbyPluginScreenRecordPlatform.instance;

  test('$MethodChannelOrbbyPluginScreenRecord is the default instance',
      () {
    expect(initialPlatform,
        isInstanceOf<MethodChannelOrbbyPluginScreenRecord>());
  });

  test('getPlatformVersion', () async {
    final plugin = OrbbyPluginScreenRecord();
    final fakePlatform = MockOrbbyPluginScreenRecordPlatform();
    OrbbyPluginScreenRecordPlatform.instance = fakePlatform;

    expect(await plugin.getPlatformVersion(), '42');
  });

  test('isSupported', () async {
    final plugin = OrbbyPluginScreenRecord();
    final fakePlatform = MockOrbbyPluginScreenRecordPlatform();
    OrbbyPluginScreenRecordPlatform.instance = fakePlatform;

    expect(await plugin.isSupported(), true);
  });

  test('startRecording returns output path', () async {
    final plugin = OrbbyPluginScreenRecord();
    final fakePlatform = MockOrbbyPluginScreenRecordPlatform();
    OrbbyPluginScreenRecordPlatform.instance = fakePlatform;

    final result = await plugin.startRecording(
      const ScreenRecordConfig(),
    );
    expect(result?['outputPath'], '/test/output.mp4');
  });

  test('stopRecording returns output path and file size', () async {
    final plugin = OrbbyPluginScreenRecord();
    final fakePlatform = MockOrbbyPluginScreenRecordPlatform();
    OrbbyPluginScreenRecordPlatform.instance = fakePlatform;

    final result = await plugin.stopRecording();
    expect(result?['outputPath'], '/test/output.mp4');
    expect(result?['fileSizeBytes'], 12345);
  });

  test('stateStream maps string to RecordState', () async {
    final fakePlatform = MockOrbbyPluginScreenRecordPlatform();
    OrbbyPluginScreenRecordPlatform.instance = fakePlatform;

    // Override to emit a specific state.
    final plugin = OrbbyPluginScreenRecord();
    expect(await plugin.stateStream.first, RecordState.idle);
  });
}
