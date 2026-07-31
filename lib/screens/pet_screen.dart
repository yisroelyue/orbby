import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart' show screenRetriever;
import 'package:window_manager/window_manager.dart';

import '../config/constants.dart';
import '../config/settings.dart';
import '../core/sub_app_registry.dart';
import '../screens/app_center_screen.dart';
import '../screens/favorites_edit_screen.dart';
import '../screens/todo_edit_screen.dart';
import '../screens/todo_item_popup.dart';
import '../services/clipboard_service.dart';
import '../services/favorites_service.dart';
import '../services/notification_service.dart';
import '../widgets/pet_ball_round.dart';
import '../widgets/pet_ball_colorful.dart';

class PetScreen extends StatefulWidget {
  const PetScreen({super.key});

  @override
  State<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends State<PetScreen> {
  static const _menuWidth = 600.0;
  static const _todoEditWidth = 800.0;
  static const _todoEditHeight = 620.0;
  static const _favoritesEditWidth = 750.0;
  static const _favoritesEditHeight = 600.0;
  static const _appCenterWidth = 720.0;
  static const _appCenterHeight = 580.0;
  static const _subAppDefaultWidth = 800.0;
  static const _subAppDefaultHeight = 600.0;
  static const _todoItemPopupWidth = 500.0;
  static const _todoItemPopupHeight = 300.0;
  static const _clipboardPopupWidth = 320.0;
  static const _clipboardPopupHeight = 400.0;
  static const _notifWidth = 400.0;
  static const _notifHeight = 400.0;
  static const _menuChannel = WindowMethodChannel(
    'orbby_menu_events',
    mode: ChannelMode.unidirectional,
  );
  static const _settingsChannel = WindowMethodChannel(
    'orbby_settings_events',
    mode: ChannelMode.unidirectional,
  );
  static const _dropChannel = MethodChannel('orbby_file_drop');
  static const _hotkeyChannel = MethodChannel('orbby_hotkey');

  WindowController? _menuWindow;
  WindowController? _todoEditWindow;
  WindowController? _favoritesEditWindow;
  WindowController? _appCenterWindow;
  WindowController? _subAppWindow;
  WindowController? _todoItemPopupWindow;
  WindowController? _clipboardPopupWindow;
  WindowController? _notifWindow;
  bool _menuVisible = false;
  bool _precreatingMenu = false;

  String _petStyle = 'colorful';

  @override
  void initState() {
    super.initState();
    _menuChannel.setMethodCallHandler(_handleMenuEvent);
    _settingsChannel.setMethodCallHandler(_handleSettingsEvent);
    _dropChannel.setMethodCallHandler(_handleDropEvent);
    _hotkeyChannel.setMethodCallHandler(_handleHotkeyEvent);
    TodoEditScreen.editChannel.setMethodCallHandler(_handleTodoEditEvent);
    TodoItemPopup.popupChannel.setMethodCallHandler(_handleTodoItemPopupEvent);
    FavoritesEditScreen.editChannel.setMethodCallHandler(
      _handleFavoritesEditEvent,
    );
    AppCenterScreen.panelChannel.setMethodCallHandler(_handleAppCenterEvent);

    // 绑定通知发送器
    NotificationService.instance.bindSender((data) async {
      try {
        if (_notifWindow == null) {
          await _createNotifWindow();
        }
        // 获取当前悬浮球位置，一并传给通知窗口
        final petPos = await windowManager.getPosition();
        final petSize = await windowManager.getSize();
        final screenBounds = await _getScreenBounds();
        data['petX'] = petPos.dx;
        data['petY'] = petPos.dy;
        data['petW'] = petSize.width;
        data['petH'] = petSize.height;
        data['screenW'] = screenBounds.width;
        data['screenH'] = screenBounds.height;
        await _notifWindow!.invokeMethod(data['method'] as String, data);
      } catch (_) {
        _notifWindow = null;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = await SettingsService.load();
      if (mounted) {
        setState(() {
          _petStyle = settings.petStyle;
        });
      }
      if (settings.enableClipboardMonitor) {
        ClipboardService.instance.start();
      }
      _precreateWindows();
    });
  }

  @override
  void dispose() {
    ClipboardService.instance.dispose();
    _notifWindow = null;
    _menuChannel.setMethodCallHandler(null);
    _settingsChannel.setMethodCallHandler(null);
    _dropChannel.setMethodCallHandler(null);
    _hotkeyChannel.setMethodCallHandler(null);
    super.dispose();
  }

  // ─── 菜单事件（来自 HomeScreen） ───────────────────────────────────────────

  Future<void> _handleMenuEvent(MethodCall call) async {
    switch (call.method) {
      case 'test_action':
        return;
      case 'open_settings':
        // 设置已集成到 HomeScreen 的设置 tab，切换过去
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('switch_tab', 2);
          } catch (_) {}
        }
        return;
      case 'exit':
        await windowManager.destroy();
        return;
      case 'open_todo_item_popup':
        final args = call.arguments;
        if (args is Map) {
          _showTodoItemPopup({
            'id': args['id'] as String? ?? '',
            'title': args['title'] as String? ?? '',
            'important': args['important'] as bool? ?? false,
          });
        }
        return;
      case 'open_todo_editor':
        final args = call.arguments;
        if (args is Map) {
          _showTodoEditor({
            'id': args['id'] as String? ?? '',
            'title': args['title'] as String? ?? '',
          });
        }
        return;
      case 'toggle_vibe_panel':
        return;
      case 'open_favorites_editor':
        final args = call.arguments;
        if (args is Map) {
          _showFavoritesEditor({
            'folderId': args['folderId'] as String? ?? '',
            'folderName': args['folderName'] as String? ?? '未分类',
          });
        }
        return;
      case 'open_app_center':
        _showAppCenter();
        return;
      case 'launch_sub_app':
        final args = call.arguments as Map;
        _showSubAppWindow(args['subAppId'] as String);
        return;
      case 'close_menu':
        _menuVisible = false;
        try {
          await _menuWindow?.hide();
        } catch (_) {}
        return;
      case 'toggle_clipboard_monitor':
        final settings = await SettingsService.load();
        if (settings.enableClipboardMonitor) {
          ClipboardService.instance.start();
        } else {
          ClipboardService.instance.stop();
        }
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  // ─── 设置事件 ──────────────────────────────────────────────────────────────

  Future<void> _handleSettingsEvent(MethodCall call) async {
    switch (call.method) {
      case 'settings_saved':
        final settings = await SettingsService.load();
        if (mounted) {
          setState(() {
            _petStyle = settings.petStyle;
          });
        }
        if (_menuWindow != null) {
          try {
            await Future.wait([
              _menuWindow!.invokeMethod('refresh_balance'),
              _menuWindow!.invokeMethod('refresh_todos'),
              _menuWindow!.invokeMethod('refresh_favorites'),
              _menuWindow!.invokeMethod('refresh_panel_apps'),
            ]);
          } catch (_) {}
        }
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  // ─── 菜单窗口 ──────────────────────────────────────────────────────────────

  /// 打开 HomeScreen 窗口（右侧面板）
  Future<void> _showMenuWindow() async {
    _menuVisible = true;

    // 等待预创建完成，避免重复创建窗口
    while (_precreatingMenu) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final menuBounds = await _getMenuBounds();

    if (_menuWindow != null) {
      try {
        await _menuWindow!.invokeMethod('place', {
          'left': menuBounds.left,
          'top': menuBounds.top,
          'width': menuBounds.width,
          'height': menuBounds.height,
        });
        return;
      } catch (_) {
        _menuWindow = null;
      }
    }

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': 'menu',
          'left': menuBounds.left,
          'top': menuBounds.top,
          'width': menuBounds.width,
          'height': menuBounds.height,
        }),
      ),
    );
    _menuWindow = createdWindow;
  }

  /// 切换 HomeScreen 显隐
  Future<void> _toggleMenuWindow() async {
    if (_menuVisible) {
      _menuVisible = false;
      try {
        await _menuWindow?.hide();
      } catch (_) {}
    } else {
      await _showMenuWindow();
    }
  }

  // ─── 各子窗口 ──────────────────────────────────────────────────────────────

  /// 显示剪贴板历史弹窗（在鼠标指针位置）
  Future<void> _showClipboardPopup() async {
    final cursorPos = _getCursorPos();

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    var left = cursorPos.dx - _clipboardPopupWidth / 2;
    var top = cursorPos.dy - _clipboardPopupHeight - 8;

    if (left < 0) left = 0;
    if (left + _clipboardPopupWidth > screenSize.width) {
      left = screenSize.width - _clipboardPopupWidth;
    }
    if (top < 0) top = cursorPos.dy + 8;

    if (_clipboardPopupWindow != null) {
      try {
        await _clipboardPopupWindow!.invokeMethod('reposition', {
          'left': left,
          'top': top,
        });
        await _clipboardPopupWindow!.show();
        return;
      } catch (_) {
        _clipboardPopupWindow = null;
      }
    }

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': 'clipboard_popup',
          'hidden': true,
          'left': left,
          'top': top,
          'width': _clipboardPopupWidth,
          'height': _clipboardPopupHeight,
        }),
      ),
    );
    _clipboardPopupWindow = createdWindow;
    await _clipboardPopupWindow!.show();
  }

  /// 获取当前鼠标指针屏幕坐标
  Offset _getCursorPos() {
    if (!Platform.isWindows) return Offset.zero;
    // POINT 结构: 2个LONG (各4字节)
    final point = pkg_ffi.calloc<ffi.Int32>(2);
    final user32 = ffi.DynamicLibrary.open('user32.dll');
    final getCursorPos = user32
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Int32>),
          int Function(ffi.Pointer<ffi.Int32>)
        >('GetCursorPos');
    if (getCursorPos(point) != 0) {
      final x = point[0];
      final y = point[1];
      pkg_ffi.calloc.free(point);
      return Offset(x.toDouble(), y.toDouble());
    }
    pkg_ffi.calloc.free(point);
    return Offset.zero;
  }

  Future<void> _precreateWindows() async {
    _precreatingMenu = true;
    // 预创建菜单窗口（优先使用固定位置，否则右侧贴边）
    if (_menuWindow == null) {
      final menuBounds = await _getMenuBounds();
      try {
        _menuWindow = await WindowController.create(
          WindowConfiguration(
            arguments: jsonEncode({
              'type': 'menu',
              'hidden': true,
              'left': menuBounds.left,
              'top': menuBounds.top,
              'width': menuBounds.width,
              'height': menuBounds.height,
            }),
          ),
        );
      } catch (_) {}
    }
    _precreatingMenu = false;

    // 预创建笔记编辑弹窗
    if (_todoItemPopupWindow == null) {
      try {
        _todoItemPopupWindow = await WindowController.create(
          WindowConfiguration(
            hiddenAtLaunch: true,
            arguments: jsonEncode({
              'type': 'todo_item_popup',
              'hidden': true,
              'id': '',
              'title': '',
              'important': false,
              'left': 0,
              'top': 0,
              'width': _todoItemPopupWidth,
              'height': _todoItemPopupHeight,
            }),
          ),
        );
      } catch (_) {}
    }

    // 注意：settings 窗口类型已从 main.dart 中移除，不再预创建
    // 设置功能已集成到 HomeScreen 的设置 tab 中

    // 预创建剪贴板弹窗（位置在 _showClipboardPopup 中动态设置）
    if (_clipboardPopupWindow == null) {
      try {
        _clipboardPopupWindow = await WindowController.create(
          WindowConfiguration(
            hiddenAtLaunch: true,
            arguments: jsonEncode({
              'type': 'clipboard_popup',
              'hidden': true,
              'left': 0,
              'top': 0,
              'width': _clipboardPopupWidth,
              'height': _clipboardPopupHeight,
            }),
          ),
        );
      } catch (_) {}
    }

    // 预创建通知窗口
    if (_notifWindow == null) await _createNotifWindow();
  }

  Future<void> _createNotifWindow() async {
    if (_notifWindow != null) return;
    try {
      _notifWindow = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({
            'type': 'notification',
            'left': 0,
            'top': 0,
            'width': _notifWidth,
            'height': _notifHeight,
          }),
        ),
      );
    } catch (_) {
      _notifWindow = null;
    }
  }

  // ─── 文件拖放 ──────────────────────────────────────────────────────────────

  Future<void> _handleDropEvent(MethodCall call) async {
    switch (call.method) {
      case 'filesDropped':
        final files = (call.arguments as List).cast<String>();
        for (final path in files) {
          final file = File(path);
          if (await file.exists()) {
            await FavoritesService.add(path);
          }
        }
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('refresh_favorites');
          } catch (_) {}
        }
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  // ─── 快捷键 ────────────────────────────────────────────────────────────────

  Future<void> _handleHotkeyEvent(MethodCall call) async {
    switch (call.method) {
      case 'toggle_menu':
        if (_menuVisible) {
          _menuVisible = false;
          try {
            await _menuWindow?.hide();
          } catch (_) {}
        } else {
          await _showMenuWindow();
          if (_menuWindow != null) {
            try {
              await _menuWindow!.invokeMethod('switch_tab', 0);
            } catch (_) {}
          }
        }
        return;
      case 'open_settings':
        // 设置已集成到 HomeScreen 的设置 tab，打开菜单并切换
        await _showMenuWindow();
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('switch_tab', 2);
          } catch (_) {}
        }
        return;
      case 'toggle_agent':
        if (_menuVisible) {
          _menuVisible = false;
          try {
            await _menuWindow?.hide();
          } catch (_) {}
        } else {
          await _showMenuWindow();
          if (_menuWindow != null) {
            try {
              await _menuWindow!.invokeMethod('switch_tab', 1);
            } catch (_) {}
          }
        }
        return;
      case 'show_clipboard':
        final settings = await SettingsService.load();
        if (settings.enableClipboardMonitor) {
          _showClipboardPopup();
        }
        return;
      case 'clipboard_changed':
        ClipboardService.instance.onClipboardChanged();
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  // ─── Todo / 收藏 / 应用中心事件 ────────────────────────────────────────────

  Future<void> _handleTodoEditEvent(MethodCall call) async {
    switch (call.method) {
      case 'todo_saved':
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('refresh_todos');
          } catch (_) {}
        }
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _handleTodoItemPopupEvent(MethodCall call) async {
    switch (call.method) {
      case 'todo_item_saved':
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('refresh_todos');
          } catch (_) {}
        }
        return;
      case 'todo_item_marked':
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('refresh_todos');
          } catch (_) {}
        }
        return;
      case 'todo_item_dismissed':
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _handleFavoritesEditEvent(MethodCall call) async {
    switch (call.method) {
      case 'favorites_changed':
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('refresh_favorites');
          } catch (_) {}
        }
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _handleAppCenterEvent(MethodCall call) async {
    switch (call.method) {
      case 'panel_changed':
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('refresh_panel_apps');
          } catch (_) {}
        }
        return;
      case 'launch_sub_app':
        final args = call.arguments as Map;
        _showSubAppWindow(args['subAppId'] as String);
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  // ─── 子窗口创建 ────────────────────────────────────────────────────────────

  Future<void> _showFavoritesEditor(Map<String, dynamic> args) async {
    try {
      await _favoritesEditWindow?.hide();
    } catch (_) {}
    _favoritesEditWindow = null;

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    final left = (screenSize.width - _favoritesEditWidth) / 2;
    final top = (screenSize.height - _favoritesEditHeight) / 2;

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'favorites_edit',
          'folderId': args['folderId'],
          'folderName': args['folderName'],
          'left': left,
          'top': top,
          'width': _favoritesEditWidth,
          'height': _favoritesEditHeight,
        }),
      ),
    );
    _favoritesEditWindow = createdWindow;
  }

  Future<void> _showAppCenter() async {
    try {
      await _appCenterWindow?.hide();
    } catch (_) {}
    _appCenterWindow = null;

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    final left = (screenSize.width - _appCenterWidth) / 2;
    final top = (screenSize.height - _appCenterHeight) / 2;

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'app_center',
          'left': left,
          'top': top,
          'width': _appCenterWidth,
          'height': _appCenterHeight,
        }),
      ),
    );
    _appCenterWindow = createdWindow;
  }

  Future<void> _showSubAppWindow(String subAppId) async {
    try {
      await _subAppWindow?.hide();
    } catch (_) {}
    _subAppWindow = null;

    final subApp = SubAppRegistry.byId(subAppId);
    final preferredSize =
        subApp?.preferredWindowSize ??
        const Size(_subAppDefaultWidth, _subAppDefaultHeight);

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    final left = (screenSize.width - preferredSize.width) / 2;
    final top = (screenSize.height - preferredSize.height) / 2;

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'sub_app',
          'subAppId': subAppId,
          'left': left,
          'top': top,
          'width': preferredSize.width,
          'height': preferredSize.height,
        }),
      ),
    );
    _subAppWindow = createdWindow;
  }

  Future<void> _showTodoItemPopup(Map<String, dynamic> item) async {
    final screenBounds = await _getScreenBounds();
    // 弹窗定位在 menu（屏幕右边缘，宽 _menuWidth）左侧，留 8px 间距
    final popupLeft =
        (screenBounds.right - _menuWidth - _todoItemPopupWidth - 8).clamp(
          0.0,
          screenBounds.right - _todoItemPopupWidth,
        );
    final popupTop = (screenBounds.height - _todoItemPopupHeight) / 2;

    if (_todoItemPopupWindow != null) {
      try {
        await _todoItemPopupWindow!.invokeMethod('set_data', {
          'id': item['id'],
          'title': item['title'],
          'important': item['important'],
          'left': popupLeft,
          'top': popupTop,
          'width': _todoItemPopupWidth,
          'height': _todoItemPopupHeight,
        });
        return;
      } catch (_) {
        _todoItemPopupWindow = null;
      }
    }

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': 'todo_item_popup',
          'id': item['id'],
          'title': item['title'],
          'important': item['important'],
          'left': popupLeft,
          'top': popupTop,
          'width': _todoItemPopupWidth,
          'height': _todoItemPopupHeight,
        }),
      ),
    );
    _todoItemPopupWindow = createdWindow;
  }

  Future<void> _showTodoEditor(Map<String, dynamic> item) async {
    try {
      await _todoEditWindow?.hide();
    } catch (_) {}
    _todoEditWindow = null;

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    final left = (screenSize.width - _todoEditWidth) / 2;
    final top = (screenSize.height - _todoEditHeight) / 2;

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'todo_edit',
          'focusId': item['id'],
          'left': left,
          'top': top,
          'width': _todoEditWidth,
          'height': _todoEditHeight,
        }),
      ),
    );
    _todoEditWindow = createdWindow;
  }

  // ─── 工具 ──────────────────────────────────────────────────────────────────

  Future<Rect> _getScreenBounds() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return position & size;
  }

  /// 获取菜单窗口 bounds：主屏右侧贴边
  Future<Rect> _getMenuBounds() async {
    final screenBounds = await _getScreenBounds();
    return Rect.fromLTWH(
      screenBounds.right - _menuWidth,
      screenBounds.top,
      _menuWidth,
      screenBounds.height,
    );
  }

  // ─── 构建 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _PetBody(petStyle: _petStyle);
  }
}

class _PetBody extends StatefulWidget {
  const _PetBody({required this.petStyle});

  final String petStyle;

  @override
  State<_PetBody> createState() => _PetBodyState();
}

class _PetBodyState extends State<_PetBody> {
  bool _hovered = false;
  bool _notifShowing = false;
  Offset? _dragStartScreenPos;
  Offset? _dragStartWindowPos;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.isShowingNotifier.addListener(_onNotifChanged);
  }

  @override
  void dispose() {
    NotificationService.instance.isShowingNotifier.removeListener(
      _onNotifChanged,
    );
    super.dispose();
  }

  void _onNotifChanged() {
    if (!mounted) return;
    setState(() {
      _notifShowing = NotificationService.instance.isShowingNotifier.value;
    });
  }

  Future<void> _onPanStart(DragStartDetails details) async {
    _dragStartScreenPos = await _getCursorScreenPos();
    final pos = await windowManager.getPosition();
    _dragStartWindowPos = pos;
  }

  Future<void> _onPanUpdate(DragUpdateDetails details) async {
    if (_dragStartScreenPos == null || _dragStartWindowPos == null) return;
    final currentPos = await _getCursorScreenPos();
    final dx = currentPos.dx - _dragStartScreenPos!.dx;
    final dy = currentPos.dy - _dragStartScreenPos!.dy;

    final newPos = Offset(
      _dragStartWindowPos!.dx + dx,
      _dragStartWindowPos!.dy + dy,
    );
    await windowManager.setPosition(newPos);
  }

  void _onPanEnd(DragEndDetails _) {
    _dragStartScreenPos = null;
    _dragStartWindowPos = null;
  }

  Future<Offset> _getCursorScreenPos() async {
    if (!Platform.isWindows) return Offset.zero;
    final point = pkg_ffi.calloc<ffi.Int32>(2);
    final user32 = ffi.DynamicLibrary.open('user32.dll');
    final getCursorPos = user32
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Int32>),
          int Function(ffi.Pointer<ffi.Int32>)
        >('GetCursorPos');
    if (getCursorPos(point) != 0) {
      final x = point[0];
      final y = point[1];
      pkg_ffi.calloc.free(point);
      return Offset(x.toDouble(), y.toDouble());
    }
    pkg_ffi.calloc.free(point);
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final now = DateTime.now();
        final hour = now.hour;
        String greeting;
        NotificationLevel level;
        if (hour < 6) {
          greeting = '夜深了，注意休息 🌙';
          level = NotificationLevel.info;
        } else if (hour < 12) {
          greeting = '早上好！新的一天开始了 ☀️';
          level = NotificationLevel.success;
        } else if (hour < 18) {
          greeting = '下午好！继续加油 💪';
          level = NotificationLevel.success;
        } else if (hour < 22) {
          greeting = '晚上好！今天的任务完成了吗？🌟';
          level = NotificationLevel.warning;
        } else {
          greeting = '夜深了，注意休息 🌙';
          level = NotificationLevel.info;
        }
        NotificationService.instance.show(
          title: 'Orbby',
          message: greeting,
          level: level,
          duration: const Duration(seconds: 3),
        );
      },
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: PetConfig.windowPaddingH,
          vertical: PetConfig.windowPaddingV,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedScale(
            scale: (_hovered || _notifShowing) ? 1.4 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              width: PetConfig.ballSize,
              height: PetConfig.ballSize,
              child: widget.petStyle == 'colorful'
                  ? const PetBallColorful()
                  : const PetBallRound(),
            ),
          ),
        ),
      ),
    );
  }
}
