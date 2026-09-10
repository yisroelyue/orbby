import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app_events.dart';

/// Hidden primary-engine coordinator for native hotkeys and secondary windows.
class WindowCoordinator extends StatefulWidget {
  const WindowCoordinator({super.key});

  @override
  State<WindowCoordinator> createState() => _WindowCoordinatorState();
}

class _WindowCoordinatorState extends State<WindowCoordinator> {
  static const _menuWidthFactor = 1 / 3;
  static const _appCenterWidth = 720.0;
  static const _appCenterHeight = 580.0;
  static const _appBarHeight = 80.0;
  static const _contentWidthFactor = 1 / 6;

  static const _menuChannel = WindowMethodChannel(
    'orbby_menu_events', mode: ChannelMode.unidirectional,
  );
  static const _settingsChannel = WindowMethodChannel(
    'orbby_settings_events', mode: ChannelMode.unidirectional,
  );
  static const _hotkeyChannel = MethodChannel('orbby_hotkey');
  static const _dropChannel = MethodChannel('orbby_file_drop');
  static const _appBarChannel = WindowMethodChannel(
    'orbby_app_bar_events', mode: ChannelMode.unidirectional,
  );
  static const _contentChannel = WindowMethodChannel(
    'orbby_content_events', mode: ChannelMode.unidirectional,
  );

  WindowController? _menuWindow;
  WindowController? _appBarWindow;
  WindowController? _contentWindow;
  WindowController? _appCenterWindow;
  WindowController? _settingsWindow;
  Completer<void>? _menuReady;
  Completer<void>? _appBarReady;
  Completer<void>? _contentReady;
  Completer<void>? _settingsReady;
  bool _menuVisible = false;
  bool _appBarVisible = false;
  bool _contentVisible = false;
  bool _settingsVisible = false;
  Future<void> _menuOperation = Future.value();
  Future<void> _appBarOperation = Future.value();
  Future<void> _contentOperation = Future.value();
  Future<void> _settingsOperation = Future.value();

  @override
  void initState() {
    super.initState();
    _menuChannel.setMethodCallHandler(_handleMenuEvent);
    _settingsChannel.setMethodCallHandler(_handleSettingsEvent);
    _hotkeyChannel.setMethodCallHandler(_handleHotkeyEvent);
    _dropChannel.setMethodCallHandler(_handleDropEvent);
    _appBarChannel.setMethodCallHandler((call) async {
      if (call.method == 'ready' && _appBarReady != null && !_appBarReady!.isCompleted) {
        _appBarReady!.complete();
      } else if (call.method == 'hidden') {
        _appBarVisible = false;
      }
    });
    _contentChannel.setMethodCallHandler((call) async {
      if (call.method == 'ready' && _contentReady != null && !_contentReady!.isCompleted) {
        _contentReady!.complete();
      } else if (call.method == 'hidden') {
        _contentVisible = false;
      }
    });
    AppEvents.initHub(_broadcastEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precreateWindows());
  }

  @override
  void dispose() {
    _menuChannel.setMethodCallHandler(null);
    _settingsChannel.setMethodCallHandler(null);
    _hotkeyChannel.setMethodCallHandler(null);
    _dropChannel.setMethodCallHandler(null);
    _appBarChannel.setMethodCallHandler(null);
    _contentChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleMenuEvent(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        if (_menuReady != null && !_menuReady!.isCompleted) _menuReady!.complete();
        return null;
      case 'open_settings':
        await _toggleSettings();
        return null;
      case 'open_app_center':
        await _showAppCenter();
        return null;
      case 'close_menu':
        _menuVisible = false;
        await _menuWindow?.hide();
        return null;
      default:
        return null;
    }
  }

  Future<dynamic> _handleSettingsEvent(MethodCall call) async {
    if (call.method == 'ready' && _settingsReady != null && !_settingsReady!.isCompleted) {
      _settingsReady!.complete();
    } else if (call.method == 'hidden') {
      _settingsVisible = false;
    }
  }

  Future<dynamic> _handleDropEvent(MethodCall call) async => null;

  Future<dynamic> _handleHotkeyEvent(MethodCall call) async {
    switch (call.method) {
      case 'toggle_menu':
        if (_menuVisible) {
          _menuVisible = false;
          await _menuWindow?.hide();
        } else {
          await _showMenu();
        }
        return null;
      case 'open_settings':
        await _toggleSettings();
        return null;
      case 'toggle_app_bar':
        await _toggleAppBar();
        return null;
      case 'toggle_content':
        await _toggleContent();
        return null;
    }
  }

  /// 把事件转发给所有子窗口；未创建或已销毁的窗口忽略
  void _broadcastEvent(String event) {
    for (final window in [_menuWindow, _appBarWindow, _contentWindow, _appCenterWindow, _settingsWindow]) {
      window?.invokeMethod('app_event', event).catchError((_) => null);
    }
  }

  /// 设置窗口：60% 屏幕宽高，居中
  Map<String, double> _settingsBounds(Size size) => {
        'left': size.width * 0.2,
        'top': size.height * 0.2,
        'width': size.width * 0.6,
        'height': size.height * 0.6,
      };

  /// 创建（如未创建）设置窗口并等待其 engine 就绪；不负责显示
  Future<void> _createSettingsWindow() async {
    if (_settingsWindow != null) return;
    _settingsReady = Completer<void>();
    _settingsWindow = await WindowController.create(WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode({'type': 'settings', ..._settingsBounds(await _screenSize())}),
    ));
    try { await _settingsReady!.future.timeout(const Duration(seconds: 5)); } catch (_) {}
    _settingsReady = null;
  }

  Future<void> _toggleSettings() async {
    _settingsOperation = _settingsOperation.then((_) async {
      if (_settingsVisible) { _settingsVisible = false; await _settingsWindow?.hide(); return; }
      await _createSettingsWindow();
      await _settingsWindow!.invokeMethod('place', _settingsBounds(await _screenSize()));
      _settingsVisible = true;
    }).catchError((_) {});
    await _settingsOperation;
  }

  Future<void> _showMenu({bool show = true}) async {
    _menuOperation = _menuOperation.then((_) async {
      final bounds = await _menuBounds();
      if (_menuWindow == null) {
        _menuReady = Completer<void>();
        _menuWindow = await WindowController.create(WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({'type': 'menu', 'hidden': true, ..._mapBounds(bounds)}),
        ));
        try { await _menuReady!.future.timeout(const Duration(seconds: 5)); } catch (_) {}
        _menuReady = null;
      }
      if (show) {
        await _menuWindow!.invokeMethod('place', _mapBounds(bounds));
        _menuVisible = true;
      }
    }).catchError((_) {});
    await _menuOperation;
  }

  Future<void> _toggleAppBar() async {
    _appBarOperation = _appBarOperation.then((_) async {
      if (_appBarVisible) { _appBarVisible = false; await _appBarWindow?.hide(); return; }
      final size = await _screenSize();
      final width = size.width * .3;
      final args = {'left': (size.width - width) / 2, 'top': size.height - _appBarHeight - 10, 'width': width, 'height': _appBarHeight};
      if (_appBarWindow == null) {
        // 等子窗口 engine 就绪（handler 注册后发回 ready）再 place，否则首次 place 丢失。
        _appBarReady = Completer<void>();
        _appBarWindow = await WindowController.create(WindowConfiguration(hiddenAtLaunch: true, arguments: jsonEncode({'type': 'app_bar', ...args})));
        try { await _appBarReady!.future.timeout(const Duration(seconds: 5)); } catch (_) {}
        _appBarReady = null;
      }
      await _appBarWindow!.invokeMethod('place', args);
      _appBarVisible = true;
    }).catchError((_) {});
    await _appBarOperation;
  }

  Future<void> _toggleContent() async {
    _contentOperation = _contentOperation.then((_) async {
      if (_contentVisible) { _contentVisible = false; await _contentWindow?.hide(); return; }
      final size = await _screenSize();
      final width = size.width * _contentWidthFactor;
      final args = {'left': size.width - width - 16, 'top': 16.0, 'width': width, 'height': size.height - 32};
      if (_contentWindow == null) {
        _contentReady = Completer<void>();
        _contentWindow = await WindowController.create(WindowConfiguration(hiddenAtLaunch: true, arguments: jsonEncode({'type': 'content', ...args})));
        try { await _contentReady!.future.timeout(const Duration(seconds: 5)); } catch (_) {}
        _contentReady = null;
      }
      await _contentWindow!.invokeMethod('place', args);
      _contentVisible = true;
    }).catchError((_) {});
    await _contentOperation;
  }

  Future<void> _showAppCenter() async {
    await _appCenterWindow?.hide();
    final size = await _screenSize();
    _appCenterWindow = await WindowController.create(WindowConfiguration(arguments: jsonEncode({'type': 'app_center', 'left': (size.width - _appCenterWidth) / 2, 'top': (size.height - _appCenterHeight) / 2, 'width': _appCenterWidth, 'height': _appCenterHeight})));
  }

  Future<void> _precreateWindows() async {
    await _showMenu(show: false);
    // 设置窗口预创建：启动时加载 engine，打开时无需等待。
    _settingsOperation = _settingsOperation.then((_) => _createSettingsWindow()).catchError((_) {});
    await _settingsOperation;
  }

  Future<Size> _screenSize() async {
    final display = await screenRetriever.getPrimaryDisplay();
    return display.visibleSize ?? display.size;
  }

  Future<Rect> _menuBounds() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    final width = size.width * _menuWidthFactor;
    return Rect.fromLTWH(position.dx + size.width - width, position.dy, width, size.height);
  }

  Map<String, double> _mapBounds(Rect bounds) => {'left': bounds.left, 'top': bounds.top, 'width': bounds.width, 'height': bounds.height};

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
