import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'config/constants.dart';
import 'config/settings.dart';
import 'screens/about_screen.dart';
import 'screens/app_bar_screen.dart';
import 'screens/app_center_screen.dart';
import 'screens/home_screen.dart';
import 'screens/content_screen.dart';
import 'services/llm_task.dart';
import 'services/log_service.dart';


const _windowShapeChannel = MethodChannel('orbby_window_shape');

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 注入今天日期，供 LLM 任务获取实时数据
  final now = DateTime.now();
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  LlmTask.today =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}（星期${weekdays[now.weekday - 1]}）';

  await LogService.init();

  await windowManager.ensureInitialized();

  final windowController = await WindowController.fromCurrentEngine();
  final windowArguments = _parseWindowArguments(windowController.arguments);
  if (windowArguments['type'] == 'menu') {
    await Window.initialize();
    await _configureMenuWindow(windowController, windowArguments);
    runApp(const HomeScreen());
    return;
  }
  if (windowArguments['type'] == 'app_bar') {
    await Window.initialize();
    await _configureAppBarWindow(windowController, windowArguments);
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Microsoft YaHei',
        ),
        home: const AppBarScreen(),
      ),
    );
    return;
  }
  if (windowArguments['type'] == 'content') {
    await Window.initialize();
    await _configureContentWindow(windowController, windowArguments);
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          fontFamily: 'Microsoft YaHei',
        ),
        home: const ContentScreen(),
      ),
    );
    return;
  }
  if (windowArguments['type'] == 'app_center') {
    await Window.initialize();
    await _configureAppCenterWindow(windowController, windowArguments);
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Microsoft YaHei',
        ),
        home: const AppCenterScreen(),
      ),
    );
    return;
  }
  if (windowArguments['type'] == 'about') {
    await Window.initialize();
    await _configureAboutWindow(windowController, windowArguments);
    runApp(const AboutScreen());
    return;
  }
  await Window.initialize();
  await _configurePetWindow();
  // PetScreen 需要挂载以注册全局快捷键，但窗口保持隐藏。
  await windowManager.hide();
  await _ensureSettingsFile();

  runApp(const OrbbyApp());
  _initSystemTray();
}

Future<void> _initSystemTray() async {
  try {
    final tmpDir = await getTemporaryDirectory();
    final icoFile = File('${tmpDir.path}/orbby_tray.ico');
    final data = await rootBundle.load('assets/logo_out.ico');
    await icoFile.writeAsBytes(data.buffer.asUint8List());

    final systemTray = SystemTray();
    await systemTray.initSystemTray(iconPath: icoFile.path, toolTip: 'Orbby');

    // On Windows, right-click events must be handled manually to show the menu.
    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: '关于', onClicked: (_) => _openAboutFromTray()),
      MenuItemLabel(
        label: '退出',
        onClicked: (_) async {
          await windowManager.hide();
          await systemTray.destroy();
          exit(0);
        },
      ),
    ]);
    await systemTray.setContextMenu(menu);
  } catch (e, st) {
    LogService.error('System tray init failed', exception: e, stack: st);
  }
}

Future<void> _openAboutFromTray() async {
  const aboutWidth = 1200.0;
  const aboutHeight = 720.0;

  final display = await screenRetriever.getPrimaryDisplay();
  final screenSize = display.visibleSize ?? display.size;
  final left = (screenSize.width - aboutWidth) / 2;
  final top = (screenSize.height - aboutHeight) / 2;

  await WindowController.create(
    WindowConfiguration(
      arguments: jsonEncode({
        'type': 'about',
        'left': left,
        'top': top,
        'width': aboutWidth,
        'height': aboutHeight,
      }),
    ),
  );
}

Future<void> _ensureSettingsFile() async {
  final settings = await SettingsService.load();
  await SettingsService.save(settings);
  LogService.updateConfig(settings.logCategories);
}

Map<String, dynamic> _parseWindowArguments(String arguments) {
  if (arguments.isEmpty) {
    return const {};
  }

  final decoded = jsonDecode(arguments);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }

  return const {};
}

Future<void> _configurePetWindow() async {
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(PetConfig.windowWidth, PetConfig.windowHeight),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
    ),
    () async {
      const size = Size(PetConfig.windowWidth, PetConfig.windowHeight);

      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);

      // 锁死窗口尺寸
      await windowManager.setMinimumSize(size);
      await windowManager.setMaximumSize(size);
      await windowManager.setSize(size);

      // 初始位置：屏幕右下角可见区域
      final display = await screenRetriever.getPrimaryDisplay();
      final screenSize = display.visibleSize ?? display.size;
      final x = screenSize.width - PetConfig.windowWidth - 5;
      final y = screenSize.height - PetConfig.windowHeight - 5;
      await windowManager.setPosition(Offset(x, y));

      // 透明背景
      await windowManager.setBackgroundColor(Colors.transparent);

      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setPreventClose(true);
      await windowManager.setTitle('Orbby');
    },
  );
}

Future<void> _configureMenuWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
  await windowController.setWindowMethodHandler((call) async {
    switch (call.method) {
      case 'place':
        final args = call.arguments as Map;
        await _placeMenuWindow(_boundsFromArguments(args));
        return;
      case 'switch_tab':
        final tabIndex = call.arguments as int;
        HomeScreen.triggerTabSwitch(tabIndex);
        return;
      default:
        throw UnimplementedError('Not implemented: ${call.method}');
    }
  });

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: bounds.size,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: false,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(Size(bounds.width, 200));
      await windowManager.setBounds(bounds);
      await windowManager.setResizable(true);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setTitle('Orbby Menu');
      if (arguments['hidden'] != true) {
        await windowManager.show(inactive: true);
      }
      await _applyMenuWindowEffects();
    },
  );
}

Future<void> _configureAppBarWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
  await windowController.setWindowMethodHandler((call) async {
    if (call.method == 'place') {
      await windowManager.setBounds(_boundsFromArguments(call.arguments as Map));
      await windowManager.show();
      return;
    }
    if (call.method == 'refresh_apps') {
      AppBarScreen.refreshNotifier.value++;
      return;
    }
    throw UnimplementedError('Not implemented: ${call.method}');
  });
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: bounds.size,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: true,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(bounds.size);
      await windowManager.setMaximumSize(bounds.size);
      await windowManager.setBounds(bounds);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlwaysOnTop(true);
      // 创建阶段保持隐藏，由 place 消息完成定位并显示，避免左上角闪烁。
    },
  );
}

Future<void> _configureContentWindow(WindowController controller, Map<String, dynamic> args) async {
  final bounds = _boundsFromArguments(args);
  await windowManager.waitUntilReadyToShow(WindowOptions(
    size: bounds.size, backgroundColor: Colors.transparent, skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden, windowButtonVisibility: false, alwaysOnTop: true,
  ), () async {
    await windowManager.setAsFrameless();
    await windowManager.setBounds(bounds);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.hide();
  });
}

Future<void> _configureAppCenterWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: bounds.size,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: false,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(bounds.size);
      await windowManager.setMaximumSize(bounds.size);
      await windowManager.setBounds(bounds);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setTitle('Orbby App Center');
      await windowManager.show();
    },
  );
}

Future<void> _configureAboutWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: bounds.size,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: false,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(bounds.size);
      await windowManager.setMaximumSize(bounds.size);
      await windowManager.setBounds(bounds);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setBackgroundColor(const Color(0xFF1E1E1E));
      await windowManager.setSkipTaskbar(false);
      await windowManager.setTitle('About Orbby');
      await windowManager.setPreventClose(true);
      await windowManager.show();
    },
  );
}

Future<void> _applyMenuWindowEffects() async {
  // await _applyMenuAcrylic();
  if (Platform.isWindows) {
    await _windowShapeChannel.invokeMethod('clearRoundedRegion');
  }
}

Future<void> _placeMenuWindow(Rect bounds) async {
  await windowManager.setMinimumSize(Size(bounds.width, 200));
  await windowManager.setBounds(bounds);
  // 特效已在 _configureMenuWindow 中应用，hide/show 不会清除，
  // 无需重复设置，避免 setEffect + show 时序竞争导致毛玻璃不生效。
  await windowManager.show(inactive: true);
}

Rect _boundsFromArguments(Map arguments) {
  final left = _asDouble(arguments['left']);
  final top = _asDouble(arguments['top']);
  final width = _asDouble(arguments['width']);
  final height = _asDouble(arguments['height']);
  return Rect.fromLTWH(left, top, width, height);
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0.0;
}
