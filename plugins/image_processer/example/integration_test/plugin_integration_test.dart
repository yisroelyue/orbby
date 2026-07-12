import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ImageProcessor basic test', (WidgetTester tester) async {
    // Verify the ImageProcessor class is available
    expect(ImageProcessor, isNotNull);
  });
}
