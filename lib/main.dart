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
import 'core/sub_app_bootstrap.dart';
import 'screens/about_screen.dart';
import 'screens/app_center_screen.dart';
import 'screens/favorites_edit_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sub_app_window_screen.dart';
import 'screens/todo_edit_screen.dart';
import 'screens/todo_item_popup.dart';
import 'screens/agent_chat_popup.dart';
import 'widgets/agent_chat_panel.dart';
import 'services/log_service.dart';

import 'screens/vibe_task_screen.dart';

const _menuCornerRadius = 0.0;
const _settingsCornerRadius = 0.0;
const _windowShapeChannel = MethodChannel('orbby_window_shape');

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.init();
  LogService.info('Orbby starting | args: $args');

  await windowManager.ensureInitialized();
  bootstrapSubApps();

  final windowController = await WindowController.fromCurrentEngine();
  LogService.info('Window controller ready | id=${windowController.windowId}');
  final windowArguments = _parseWindowArguments(windowController.arguments);
  if (windowArguments['type'] == 'menu') {
    await Window.initialize();
    await _configureMenuWindow(windowController, windowArguments);
    runApp(const MenuScreen());
    return;
  }
  if (windowArguments['type'] == 'settings') {
    await Window.initialize();
    await _configureSettingsWindow(windowController, windowArguments);
    runApp(const SettingsScreen());
    return;
  }
  if (windowArguments['type'] == 'vibe_task') {
    await _configureVibeTaskWindow(windowController, windowArguments);
    runApp(const VibeTaskScreen());
    return;
  }
  if (windowArguments['type'] == 'todo_edit') {
    await Window.initialize();
    await _configureTodoEditWindow(windowController, windowArguments);
    runApp(const TodoEditScreen());
    return;
  }
  if (windowArguments['type'] == 'todo_item_popup') {
    await Window.initialize();
    await _configureTodoItemPopupWindow(windowController, windowArguments);
    runApp(const TodoItemPopup());
    return;
  }
  if (windowArguments['type'] == 'agent_chat_popup') {
    await Window.initialize();
    await _configureAgentChatPopupWindow(windowController, windowArguments);
    runApp(const AgentChatPopup());
    return;
  }
  if (windowArguments['type'] == 'favorites_edit') {
    await Window.initialize();
    await _configureFavoritesEditWindow(windowController, windowArguments);
    final fid = windowArguments['folderId'] as String?;
    runApp(FavoritesEditScreen(
      initialFolderId: (fid != null && fid.isNotEmpty) ? fid : null,
    ));
    return;
  }
  if (windowArguments['type'] == 'app_center') {
    await Window.initialize();
    await _configureAppCenterWindow(windowController, windowArguments);
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSansSC'),
      home: const AppCenterScreen(),
    ));
    return;
  }
  if (windowArguments['type'] == 'sub_app') {
    await Window.initialize();
    await _configureSubAppWindow(windowController, windowArguments);
    final subAppId = windowArguments['subAppId'] as String? ?? '';
    runApp(SubAppWindowScreen(subAppId: subAppId));
    return;
  }
  if (windowArguments['type'] == 'about') {
    await Window.initialize();
    await _configureAboutWindow(windowController, windowArguments);
    runApp(const AboutScreen());
    return;
  }

  await _configurePetWindow();
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
    await systemTray.initSystemTray(
      iconPath: icoFile.path,
      toolTip: 'Orbby',
    );

    // On Windows, right-click events must be handled manually to show the menu.
    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: '设置',
        onClicked: (_) => _openSettingsFromTray(),
      ),
      MenuItemLabel(
        label: '关于',
        onClicked: (_) => _openAboutFromTray(),
      ),
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
    LogService.error('System tray init failed', e, st);
  }
}

Future<void> _openSettingsFromTray() async {
  const settingsWidth = 900.0;
  const settingsHeight = 640.0;

  final display = await screenRetriever.getPrimaryDisplay();
  final screenSize = display.visibleSize ?? display.size;
  final left = (screenSize.width - settingsWidth) / 2;
  final top = (screenSize.height - settingsHeight) / 2;

  await WindowController.create(
    WindowConfiguration(
      arguments: jsonEncode({
        'type': 'settings',
        'left': left,
        'top': top,
        'width': settingsWidth,
        'height': settingsHeight,
      }),
    ),
  );
}

Future<void> _openAboutFromTray() async {
  const aboutWidth = 400.0;
  const aboutHeight = 510.0;

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

      // Windows runner 已用 WS_POPUP 创建原生无边框窗口，这里只同步插件状态。
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);

      // 锁死窗口尺寸为精确正方形。
      await windowManager.setMinimumSize(size);
      await windowManager.setMaximumSize(size);
      await windowManager.setSize(size);

      // 初始位置：屏幕右侧，任务栏上方
      final display = await screenRetriever.getPrimaryDisplay();
      final screenSize = display.visibleSize ?? display.size;
      final inset = 4.0;
      final x = screenSize.width - PetConfig.windowWidth - inset;
      final y = screenSize.height - PetConfig.windowHeight - 4;
      await windowManager.setPosition(Offset(x, y));

      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setBackgroundColor(Colors.transparent);
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
      case 'refresh_balance':
        MenuScreen.triggerRefresh();
        return;
      case 'refresh_todos':
        MenuScreen.triggerTodoRefresh();
        return;
      case 'refresh_favorites':
        MenuScreen.triggerFavoritesRefresh();
        return;
      case 'refresh_panel_apps':
        MenuScreen.triggerRefresh();
        return;
      case 'set_chat_loading':
        final loading = (call.arguments as Map)['loading'] as bool? ?? false;
        AgentChatPanel.chatLoadingNotifier.value = loading;
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
      alwaysOnTop: true,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(bounds.size);
      await windowManager.setMaximumSize(bounds.size);
      await windowManager.setBounds(bounds);
      await windowManager.setAlwaysOnTop(true);
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

Future<void> _configureSettingsWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: bounds.size,
      backgroundColor: const Color(0xFFF5F5F5),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: false,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(true);
      await windowManager.setMinimumSize(bounds.size);
      await windowManager.setMaximumSize(bounds.size);
      await windowManager.setBounds(bounds);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setBackgroundColor(const Color(0xFFF5F5F5));
      await windowManager.setSkipTaskbar(false);
      await windowManager.setTitle('Orbby Settings');
      await windowManager.show();
      await _applySettingsWindowEffects();
    },
  );
}

Future<void> _configureVibeTaskWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
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
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setTitle('Orbby Vibe Task');
      await windowManager.show();
    },
  );
}

Future<void> _configureTodoEditWindow(
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
      await windowManager.setTitle('Orbby Todo Edit');
      await windowManager.show();
      await _applySettingsWindowEffects();
    },
  );
}

Future<void> _configureTodoItemPopupWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
  LogService.info('TodoItemPopup config | bounds: $bounds');
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
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setTitle('编辑笔记');
      // Don't show yet — the popup screen will show itself after loading data.
    },
  );
}

Future<void> _configureAgentChatPopupWindow(
  WindowController windowController,
  Map<String, dynamic> arguments,
) async {
  final bounds = _boundsFromArguments(arguments);
  LogService.info('AgentChatPopup config | bounds: $bounds');
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
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setTitle('Agent 消息');
    },
  );
}

Future<void> _configureFavoritesEditWindow(
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
      await windowManager.setTitle('Orbby Favorites');
      await windowManager.show();
      await _applySettingsWindowEffects();
    },
  );
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
      await _applySettingsWindowEffects();
    },
  );
}

Future<void> _configureSubAppWindow(
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
      await windowManager.setMinimumSize(const Size(200, 48));
      await windowManager.setBounds(bounds);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setTitle('Orbby Sub App');
      await windowManager.show();
      final noAcrylic = {'screen_record', 'image_handler'};
      if (!noAcrylic.contains(arguments['subAppId'])) {
        await _applyAcrylic();
      }
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

Future<void> _applySettingsWindowEffects() async {
  await Window.setEffect(
    effect: WindowEffect.acrylic,
    color: const Color(0xDDF2F2F2),
  );
  if (Platform.isWindows) {
    await _windowShapeChannel.invokeMethod('setRoundedRegion', {
      'radius': _settingsCornerRadius,
    });
  }
}

Future<void> _applyAcrylic() async {
  await Window.setEffect(
    effect: WindowEffect.acrylic,
    color: const Color(0x38BFBFBF),
  );
}

Future<void> _applyMenuWindowEffects() async {
  await _applyAcrylic();
  if (Platform.isWindows) {
    await _windowShapeChannel.invokeMethod('setRoundedRegion', {
      'radius': _menuCornerRadius,
    });
  }
}

Future<void> _placeMenuWindow(Rect bounds) async {
  await windowManager.setMinimumSize(bounds.size);
  await windowManager.setMaximumSize(bounds.size);
  await windowManager.setBounds(bounds);
  await windowManager.setAlwaysOnTop(true);
  // Apply effects BEFORE show to avoid flash of unstyled window.
  await _applyMenuWindowEffects();
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
