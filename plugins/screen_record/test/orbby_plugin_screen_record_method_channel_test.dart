import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbby_plugin_screen_record/orbby_plugin_screen_record_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelOrbbyPluginScreenRecord();
  const methodChannel = MethodChannel('orbby_plugin_screen_record');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getPlatformVersion':
          return '42';
        case 'isSupported':
          return true;
        case 'startRecording':
          return <String, dynamic>{'outputPath': '/test/output.mp4'};
        case 'pauseRecording':
        case 'resumeRecording':
          return null;
        case 'stopRecording':
          return <String, dynamic>{
            'outputPath': '/test/output.mp4',
            'fileSizeBytes': 12345,
          };
        case 'getRecordingProgress':
          return <String, dynamic>{
            'durationMs': 5000,
            'fileSizeBytes': 10000,
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('isSupported', () async {
    expect(await platform.isSupported(), true);
  });

  test('startRecording', () async {
    final result = await platform.startRecording({
      'fps': 30,
      'bitRate': 5000000,
    });
    expect(result?['outputPath'], '/test/output.mp4');
  });

  test('pauseRecording', () async {
    // Should not throw.
    await platform.pauseRecording();
  });

  test('resumeRecording', () async {
    // Should not throw.
    await platform.resumeRecording();
  });

  test('stopRecording', () async {
    final result = await platform.stopRecording();
    expect(result?['outputPath'], '/test/output.mp4');
    expect(result?['fileSizeBytes'], 12345);
  });
}
