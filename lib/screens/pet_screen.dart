import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
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
import '../screens/agent_chat_popup.dart';
import '../services/agent_service.dart';
import '../services/favorites_service.dart';
import '../widgets/pet_ball_round.dart';
import '../widgets/pet_ball_colorful.dart';

class PetScreen extends StatefulWidget {
  const PetScreen({super.key});

  @override
  State<PetScreen> createState() => _PetScreenState();
}

enum _SnapEdge { top, bottom, left, right }

class _PetScreenState extends State<PetScreen> {
  static const _menuGap = 2.0;
  static const _menuWidth = 400.0;
  static const _settingsWidth = 900.0;
  static const _settingsHeight = 640.0;
  static const _vibeWidth = 200.0;
  static const _vibeHeight = 36.0;
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
  static const _agentChatPopupWidth = 420.0;
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
  WindowController? _settingsWindow;
  WindowController? _vibeWindow;
  WindowController? _todoEditWindow;
  WindowController? _favoritesEditWindow;
  WindowController? _appCenterWindow;
  WindowController? _subAppWindow;
  WindowController? _todoItemPopupWindow;
  WindowController? _agentChatPopupWindow;
  final _agentHistory = <Map<String, String>>[];
  Timer? _hideTimer;
  Timer? _agentChatPopupHideTimer;
  bool _isHoveringPet = false;
  bool _isHoveringMenu = false;
  bool _isHoveringAgentPopup = false;
  bool _menuLocked = false;
  bool _menuVisible = false;

  // 吸附状态
  _SnapEdge _snapEdge = _SnapEdge.right;

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
    AgentChatPopup.popupChannel.setMethodCallHandler(_handleAgentChatPopupEvent);
    FavoritesEditScreen.editChannel.setMethodCallHandler(_handleFavoritesEditEvent);
    AppCenterScreen.panelChannel.setMethodCallHandler(_handleAppCenterEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = await SettingsService.load();
      if (mounted) {
        setState(() => _petStyle = settings.petStyle);
      }
      _initVibeWindow();
      _precreateWindows();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _agentChatPopupHideTimer?.cancel();
    _menuChannel.setMethodCallHandler(null);
    _settingsChannel.setMethodCallHandler(null);
    _dropChannel.setMethodCallHandler(null);
    _hotkeyChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleMenuEvent(MethodCall call) async {
    switch (call.method) {
      case 'menu_enter':
        _isHoveringPet = false;
        _isHoveringMenu = true;
        _hideTimer?.cancel();
        return;
      case 'menu_exit':
        _isHoveringMenu = false;
        _scheduleMenuHide();
        return;
      case 'test_action':
        // Placeholder for test button
        return;
      case 'open_settings':
        _showSettings();
        return;
      case 'exit':
        await windowManager.destroy();
        return;
      case 'lock_menu':
        _menuLocked = true;
        _hideTimer?.cancel();
        return;
      case 'unlock_menu':
        _menuLocked = false;
        _scheduleMenuHide();
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
        _syncVibeWindow();
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
      case 'agent_send_message':
        final args = call.arguments as Map;
        final text = args['text'] as String? ?? '';
        final mode = args['mode'] as String? ?? 'accept';
        if (text.isEmpty) return;

        // 设置面板为加载状态
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('set_chat_loading', {'loading': true});
          } catch (_) {}
        }

        // 显示用户消息
        _agentHistory.add({'role': 'user', 'content': text});
        if (_agentChatPopupWindow != null) {
          try {
            await _agentChatPopupWindow!.invokeMethod('add_message', {
              'text': text,
              'isUser': true,
            });
          } catch (_) {}
        }

        // 调用 AI API
        try {
          final reply = await AgentService.chat(
            text,
            mode: mode,
            history: _agentHistory.isNotEmpty
                ? _agentHistory.sublist(0, _agentHistory.length - 1)
                : [],
          );
          _agentHistory.add({'role': 'assistant', 'content': reply});
          if (_agentChatPopupWindow != null) {
            try {
              await _agentChatPopupWindow!.invokeMethod('add_message', {
                'text': reply,
                'isUser': false,
              });
            } catch (_) {}
          }
        } on AgentException catch (e) {
          if (_agentChatPopupWindow != null) {
            try {
              await _agentChatPopupWindow!.invokeMethod('add_message', {
                'text': e.message,
                'isUser': false,
              });
            } catch (_) {}
          }
        }
        // 清除面板加载状态
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('set_chat_loading', {'loading': false});
          } catch (_) {}
        }
        return;
      case 'agent_clear_context':
        _agentHistory.clear();
        if (_agentChatPopupWindow != null) {
          try {
            await _agentChatPopupWindow!.invokeMethod('clear_messages');
          } catch (_) {}
        }
        return;
      case 'agent_chat_enter':
        _agentChatPopupHideTimer?.cancel();
        _showAgentChatPopup();
        return;
      case 'agent_chat_exit':
        _scheduleAgentChatPopupHide();
        return;
      case 'close_menu':
        _hideMenuNow();
        _hideAgentChatPopup();
        return;
      case 'launch_sub_app':
        final args = call.arguments as Map;
        _showSubAppWindow(args['subAppId'] as String);
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _handleSettingsEvent(MethodCall call) async {
    switch (call.method) {
      case 'settings_saved':
        // 重新加载 petStyle 设置
        final settings = await SettingsService.load();
        if (mounted) {
          setState(() => _petStyle = settings.petStyle);
        }
        // 设置保存后刷新菜单面板
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
        await _syncVibeWindow();
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _showMenu() async {
    _isHoveringPet = true;
    _menuLocked = false;
    _menuVisible = true;
    _hideTimer?.cancel();

    final menuBounds = await _calculateMenuBounds();

    // 尝试复用已有 menu 窗口；channel 失效则重建
    if (_menuWindow != null) {
      try {
        await _menuWindow!.invokeMethod('place', {
          'left': menuBounds.left,
          'top': menuBounds.top,
          'width': menuBounds.width,
          'height': menuBounds.height,
        });
      } catch (_) {
        _menuWindow = null;
      }
    }

    if (_menuWindow == null) {
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
      if (!_isHoveringPet && !_isHoveringMenu) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await createdWindow.hide();
      }
    }

  }

  Future<void> _showSettings() async {
    // 每次都重建，保证最新尺寸
    try {
      await _settingsWindow?.hide();
    } catch (_) {}
    _settingsWindow = null;

    // 计算居中位置
    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    final left = (screenSize.width - _settingsWidth) / 2;
    final top = (screenSize.height - _settingsHeight) / 2;

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'settings',
          'left': left,
          'top': top,
          'width': _settingsWidth,
          'height': _settingsHeight,
        }),
      ),
    );
    _settingsWindow = createdWindow;
  }

  Future<void> _initVibeWindow() async {
    final settings = await SettingsService.load();
    if (settings.showVibePanel) {
      await _showVibeWindow();
    }
  }

  Future<void> _precreateWindows() async {
    // 预创建菜单窗口，避免首次悬停卡顿
    final screenBounds = await _getScreenBounds();
    try {
      _menuWindow = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'menu',
            'hidden': true,
            'left': screenBounds.right - _menuWidth,
            'top': screenBounds.top,
            'width': _menuWidth,
            'height': screenBounds.height,
          }),
        ),
      );
    } catch (_) {}

    // 预创建笔记编辑弹窗，避免首次点击卡顿
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

    // 预创建 agent 消息弹窗
    try {
      _agentChatPopupWindow = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'agent_chat_popup',
            'hidden': true,
            'left': 0,
            'top': 0,
            'width': _agentChatPopupWidth,
            'height': 600,
          }),
        ),
      );
    } catch (_) {}
  }

  Future<void> _syncVibeWindow() async {
    final settings = await SettingsService.load();
    if (settings.showVibePanel) {
      await _showVibeWindow();
    } else {
      await _hideVibeWindow();
    }
  }

  Future<void> _showVibeWindow() async {
    if (_vibeWindow != null) {
      try {
        await _vibeWindow!.show();
      } catch (_) {
        _vibeWindow = null;
      }
    }
    if (_vibeWindow != null) return;

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    final left = (screenSize.width - _vibeWidth) / 2;
    const top = 0.0;

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'type': 'vibe_task',
          'left': left,
          'top': top,
          'width': _vibeWidth,
          'height': _vibeHeight,
        }),
      ),
    );
    _vibeWindow = createdWindow;
  }

  Future<void> _hideVibeWindow() async {
    try {
      await _vibeWindow?.hide();
    } catch (_) {}
    _vibeWindow = null;
  }

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

  Future<void> _handleHotkeyEvent(MethodCall call) async {
    switch (call.method) {
      case 'toggle_menu':
        await _toggleMenu();
        return;
      case 'open_settings':
        _showSettings();
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _toggleMenu() async {
    if (_menuVisible) {
      _menuLocked = false;
      _hideMenuNow();
      _hideAgentChatPopup();
    } else {
      await _showMenu();
      _menuLocked = true;
      _showAgentChatPopup();
    }
  }

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
        _menuLocked = false;
        _scheduleMenuHide();
        return;
      case 'todo_item_marked':
        if (_menuWindow != null) {
          try {
            await _menuWindow!.invokeMethod('refresh_todos');
          } catch (_) {}
        }
        return;
      case 'todo_item_dismissed':
        _menuLocked = false;
        _scheduleMenuHide();
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _handleAgentChatPopupEvent(MethodCall call) async {
    switch (call.method) {
      case 'agent_chat_popup_enter':
        _isHoveringAgentPopup = true;
        return;
      case 'agent_chat_popup_exit':
        _isHoveringAgentPopup = false;
        _scheduleAgentChatPopupHide();
        return;
      case 'agent_regenerate':
        await _regenerateAgentReply();
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<void> _regenerateAgentReply() async {
    // 移除最后一条 assistant 消息
    if (_agentHistory.isNotEmpty &&
        _agentHistory.last['role'] == 'assistant') {
      _agentHistory.removeLast();
    }
    // 找到最后一条 user 消息
    final userIndex = _agentHistory.lastIndexWhere(
      (m) => m['role'] == 'user',
    );
    if (userIndex == -1) return;
    final userText = _agentHistory[userIndex]['content'] ?? '';

    // 移除弹窗中的最后一条消息
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('remove_last_message');
      } catch (_) {}
    }

    // 重新调用 AI
    try {
      final reply = await AgentService.chat(
        userText,
        history: _agentHistory.sublist(0, userIndex),
      );
      _agentHistory.add({'role': 'assistant', 'content': reply});
      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('add_message', {
            'text': reply,
            'isUser': false,
          });
        } catch (_) {}
      }
    } on AgentException catch (e) {
      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('add_message', {
            'text': e.message,
            'isUser': false,
          });
        } catch (_) {}
      }
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
    final preferredSize = subApp?.preferredWindowSize ??
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
    // Position to the left of the menu
    final menuBounds = await _calculateMenuBounds();
    final popupLeft = menuBounds.left - _todoItemPopupWidth - 8;
    final popupTop = menuBounds.top +
        (menuBounds.height - _todoItemPopupHeight) / 2 - 60;

    // Reuse existing window
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
        _menuLocked = true;
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
    _menuLocked = true;
  }

  Future<void> _showAgentChatPopup() async {
    final menuBounds = await _calculateMenuBounds();
    final popupLeft = menuBounds.left - _agentChatPopupWidth;
    final popupHeight = menuBounds.height;
    final popupTop = menuBounds.bottom - popupHeight;

    final settings = await SettingsService.load();
    final popupTheme = settings.agentChatPopupTheme;

    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('set_data', {
          'left': popupLeft,
          'top': popupTop,
          'width': _agentChatPopupWidth,
          'height': popupHeight,
          'theme': popupTheme,
        });
        return;
      } catch (_) {
        _agentChatPopupWindow = null;
      }
    }

    final createdWindow = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': 'agent_chat_popup',
          'hidden': true,
          'left': popupLeft,
          'top': popupTop,
          'width': _agentChatPopupWidth,
          'height': popupHeight,
          'theme': popupTheme,
        }),
      ),
    );
    _agentChatPopupWindow = createdWindow;
  }

  void _scheduleAgentChatPopupHide() {
    _agentChatPopupHideTimer?.cancel();
    _agentChatPopupHideTimer = Timer(const Duration(milliseconds: 200), () {
      if (_isHoveringAgentPopup || _menuLocked) {
        return;
      }
      _hideAgentChatPopup();
    });
  }

  Future<void> _hideAgentChatPopup() async {
    _agentChatPopupHideTimer?.cancel();
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.hide();
      } catch (_) {
        _agentChatPopupWindow = null;
      }
    }
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

  void _scheduleMenuHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 300), () async {
      if (_isHoveringPet || _isHoveringMenu || _menuLocked) {
        return;
      }
      _menuVisible = false;
      await _menuWindow?.hide();
    });
  }

  void _hideMenuNow() {
    _hideTimer?.cancel();
    _isHoveringPet = false;
    _isHoveringMenu = false;
    _menuLocked = false;
    _menuVisible = false;
    unawaited(_menuWindow?.hide() ?? Future<void>.value());
  }

  Future<void> _snapToNearestEdge() async {
    final bounds = await windowManager.getBounds();
    final screenBounds = await _getScreenBounds();

    final distances = <_SnapEdge, double>{
      _SnapEdge.left: (bounds.left - screenBounds.left).abs(),
      _SnapEdge.right: (screenBounds.right - bounds.right).abs(),
      _SnapEdge.top: (bounds.top - screenBounds.top).abs(),
      _SnapEdge.bottom: (screenBounds.bottom - bounds.bottom).abs(),
    };

    final nearest =
        distances.entries.reduce((a, b) => a.value < b.value ? a : b);

    double x, y;
    const inset = 4.0;
    switch (nearest.key) {
      case _SnapEdge.left:
        x = screenBounds.left + inset;
        y = bounds.top;
      case _SnapEdge.right:
        x = screenBounds.right - bounds.width - inset;
        y = bounds.top;
      case _SnapEdge.top:
        x = bounds.left;
        y = screenBounds.top + inset;
      case _SnapEdge.bottom:
        x = bounds.left;
        y = screenBounds.bottom - bounds.height - inset;
    }

    await windowManager.setPosition(Offset(x, y));

    if (nearest.key != _snapEdge) {
      setState(() => _snapEdge = nearest.key);
    }
  }

  Future<Rect> _calculateMenuBounds() async {
    final petBounds = await windowManager.getBounds();
    final screenBounds = await _getScreenBounds();

    double left, top, height;

    switch (_snapEdge) {
      case _SnapEdge.top:
        // 悬浮球在上 → 菜单在下方
        left = petBounds.center.dx - _menuWidth / 2;
        top = petBounds.bottom + _menuGap;
        // 下方可用高度 = 工作区高度 - 悬浮球高度 - 间隙，不遮挡悬浮球
        height = screenBounds.bottom - top;
        // 下方空间不够则改到上方
        if (height < 150) {
          height = petBounds.top - _menuGap - screenBounds.top;
          top = screenBounds.top;
        }
      case _SnapEdge.bottom:
        // 悬浮球在下 → 菜单在上方
        left = petBounds.center.dx - _menuWidth / 2;
        height = petBounds.top - _menuGap - screenBounds.top;
        top = petBounds.top - _menuGap - height;
        // 上方空间不够则改到下方
        if (height < 150) {
          top = petBounds.bottom + _menuGap;
          height = screenBounds.bottom - top;
        }
      case _SnapEdge.left:
        // 悬浮球在左 → 菜单在右侧
        left = petBounds.right + _menuGap;
        top = screenBounds.top;
        height = screenBounds.height;
        // 右侧空间不够则改到左侧
        if (left + _menuWidth > screenBounds.right) {
          left = petBounds.left - _menuGap - _menuWidth;
        }
      case _SnapEdge.right:
        // 悬浮球在右 → 菜单在左侧
        left = petBounds.left - _menuGap - _menuWidth;
        top = screenBounds.top;
        height = screenBounds.height;
        // 左侧空间不够则改到右侧
        if (left < screenBounds.left) {
          left = petBounds.right + _menuGap;
        }
    }

    // 限制不超出屏幕边界
    left = left.clamp(screenBounds.left, screenBounds.right - _menuWidth);
    top = top.clamp(screenBounds.top, screenBounds.bottom);
    if (top + height > screenBounds.bottom) {
      height = screenBounds.bottom - top;
    }

    return Rect.fromLTWH(left, top, _menuWidth, height);
  }

  Future<Rect> _getScreenBounds() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return position & size;
  }

  @override
  Widget build(BuildContext context) {
    return _PetBody(
      petStyle: _petStyle,
      snapEdge: _snapEdge,
      onEnter: () => _showMenu(),
      onExit: () {
        _isHoveringPet = false;
        _scheduleMenuHide();
      },
      onDragStart: () async {
        _hideMenuNow();
        await windowManager.startDragging();
        _snapToNearestEdge();
      },
    );
  }
}

class _PetBody extends StatelessWidget {
  const _PetBody({
    required this.petStyle,
    required this.snapEdge,
    required this.onEnter,
    required this.onExit,
    required this.onDragStart,
  });

  final String petStyle;
  final _SnapEdge snapEdge;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onDragStart;

  double get _rotation {
    switch (snapEdge) {
      case _SnapEdge.top:
        return 0;
      case _SnapEdge.bottom:
        return pi;
      case _SnapEdge.left:
        return -pi / 2;
      case _SnapEdge.right:
        return pi / 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: PetConfig.windowWidth,
      height: PetConfig.windowHeight,
      child: Transform.rotate(
        angle: _rotation,
        child: MouseRegion(
          onEnter: (_) => onEnter(),
          onExit: (_) => onExit(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDragStart(),
            child: petStyle == 'colorful'
                ? const PetBallColorful()
                : const PetBallRound(),
          ),
        ),
      ),
    );
  }
}