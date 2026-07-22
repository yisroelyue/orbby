import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart' show screenRetriever;
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/constants.dart';
import '../config/platform.dart';
import '../config/settings.dart';
import '../core/sub_app_registry.dart';
import '../screens/app_center_screen.dart';
import '../screens/favorites_edit_screen.dart';
import '../screens/todo_edit_screen.dart';
import '../screens/todo_item_popup.dart';
import '../screens/agent_chat_popup.dart';
import '../services/agent_service.dart';
import '../services/chat_storage_service.dart';
import '../services/favorites_service.dart';
import '../widgets/pet_ball_round.dart';
import '../widgets/pet_ball_colorful.dart';

class PetScreen extends StatefulWidget {
  const PetScreen({super.key});

  @override
  State<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends State<PetScreen> {
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
  static const _agentChatPopupWidth = 1200.0;
  static const _agentChatPopupHeight = 1000.0;
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

  // 抽屉触发区域（屏幕顶部中央）
  static const _triggerZoneWidth = 200.0;
  static const _triggerZoneHeight = 2.0;

  WindowController? _menuWindow;
  WindowController? _settingsWindow;
  WindowController? _vibeWindow;
  WindowController? _todoEditWindow;
  WindowController? _favoritesEditWindow;
  WindowController? _appCenterWindow;
  WindowController? _subAppWindow;
  WindowController? _todoItemPopupWindow;
  WindowController? _agentChatPopupWindow;
  final _agentConversations = <String, List<Map<String, String>>>{};
  String? _activeConversationId;
  bool _menuVisible = false;
  bool _agentPopupVisible = false;
  bool _agentPopupFocused = false;
  bool _agentPopupMinimized = false;

  // 抽屉状态
  bool _drawerShown = false;
  bool _drawerAnimating = false;
  Timer? _mouseMonitorTimer;
  Timer? _hideTimer;
  double _autoHideDelay = 3.0;
  double _screenWidth = 0;

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
        setState(() {
          _petStyle = settings.petStyle;
          _autoHideDelay = settings.menuAutoHideDelay;
        });
      }
      _initVibeWindow();
      _precreateWindows();
      _startMouseMonitor();
    });
  }

  @override
  void dispose() {
    _mouseMonitorTimer?.cancel();
    _hideTimer?.cancel();
    _menuChannel.setMethodCallHandler(null);
    _settingsChannel.setMethodCallHandler(null);
    _dropChannel.setMethodCallHandler(null);
    _hotkeyChannel.setMethodCallHandler(null);
    super.dispose();
  }

  // ─── 菜单事件（来自 MenuScreen） ───────────────────────────────────────────

  Future<void> _handleMenuEvent(MethodCall call) async {
    switch (call.method) {
      case 'test_action':
        return;
      case 'open_settings':
        _showSettings();
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
            _autoHideDelay = settings.menuAutoHideDelay;
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
        await _syncVibeWindow();
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  // ─── Agent 弹窗事件 ────────────────────────────────────────────────────────

  Future<void> _handleAgentChatPopupEvent(MethodCall call) async {
    switch (call.method) {
      case 'agent_regenerate':
        await _regenerateAgentReply();
        return;
      case 'popup_clear_context':
        if (_activeConversationId != null) {
          _agentConversations[_activeConversationId!]?.clear();
        }
        if (_agentChatPopupWindow != null) {
          try {
            await _agentChatPopupWindow!.invokeMethod('clear_messages');
          } catch (_) {}
        }
        return;
      case 'popup_send_message':
        final args = call.arguments as Map;
        final text = args['text'] as String? ?? '';
        final mode = args['mode'] as String? ?? 'accept';
        if (text.isEmpty) return;
        await _handlePopupSendMessage(text, mode);
        return;
      case 'popup_new_conversation':
        await _createNewConversation();
        return;
      case 'popup_switch_conversation':
        final args = call.arguments as Map;
        final id = args['id'] as String? ?? '';
        if (id.isNotEmpty) {
          await _switchConversation(id);
        }
        return;
      case 'popup_delete_conversation':
        final args = call.arguments as Map;
        final id = args['id'] as String? ?? '';
        if (id.isNotEmpty) {
          await _deleteConversation(id);
        }
        return;
      case 'popup_clear_all_conversations':
        await _clearAllConversations();
        return;
      case 'popup_focus_changed':
        final args = call.arguments as Map;
        _agentPopupFocused = args['focused'] as bool? ?? false;
        return;
      case 'popup_minimized':
        final args = call.arguments as Map;
        _agentPopupMinimized = args['minimized'] as bool? ?? false;
        if (_agentPopupMinimized) {
          _agentPopupFocused = false;
        }
        return;
      case 'popup_close':
        _hideAgentChatPopup();
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  // ─── 对话管理 ────────────────────────────────────────────────────────────

  Future<void> _createNewConversation() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _activeConversationId = id;
    _agentConversations[id] = [];

    // 通知 popup 新对话已创建
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('conversation_created', {
          'id': id,
          'title': '新对话',
        });
      } catch (_) {}
    }
  }

  Future<void> _switchConversation(String id) async {
    _activeConversationId = id;
    final messages = _agentConversations[id] ?? [];

    // 从磁盘加载（如果内存中没有）
    if (messages.isEmpty) {
      final conv = await ChatStorageService.load(id);
      if (conv != null) {
        _agentConversations[id] = conv.messages;
        // 通知 popup 加载对话消息
        if (_agentChatPopupWindow != null) {
          try {
            await _agentChatPopupWindow!.invokeMethod('conversation_loaded', {
              'messages': conv.messages,
            });
          } catch (_) {}
        }
        return;
      }
    }

    // 通知 popup 加载对话消息
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('conversation_loaded', {
          'messages': messages,
        });
      } catch (_) {}
    }
  }

  Future<void> _deleteConversation(String id) async {
    _agentConversations.remove(id);
    if (_activeConversationId == id) {
      _activeConversationId = null;
    }
    await ChatStorageService.delete(id);

    // 通知 popup 对话已删除
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('conversation_deleted', {
          'id': id,
        });
      } catch (_) {}
    }
  }

  Future<void> _clearAllConversations() async {
    _agentConversations.clear();
    _activeConversationId = null;
    await ChatStorageService.deleteAll();

    // 通知 popup 所有对话已清除
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('all_conversations_cleared');
      } catch (_) {}
    }
  }

  Future<void> _handlePopupSendMessage(String text, String mode) async {
    // 如果没有活跃对话，自动创建一个
    if (_activeConversationId == null) {
      await _createNewConversation();
    }

    final convId = _activeConversationId!;
    final messages = _agentConversations[convId] ?? [];

    // 显示用户消息
    messages.add({'role': 'user', 'content': text});
    _agentConversations[convId] = messages;

    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('add_message', {
          'text': text,
          'isUser': true,
        });
      } catch (_) {}
    }

    final history = messages.isNotEmpty
        ? messages.sublist(0, messages.length - 1)
        : <Map<String, String>>[];

    final fullReply = StringBuffer();
    final buffer = StringBuffer();
    Timer? flushTimer;

    try {
      final stream = AgentService.chatStream(
        text,
        mode: mode,
        history: history,
      );

      // 创建流式占位消息
      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('add_message', {
            'text': '',
            'isUser': false,
            'streaming': true,
          });
        } catch (_) {}
      }

      // 每 80ms 批量发送积累的 token
      flushTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        final chunk = buffer.toString();
        if (chunk.isNotEmpty) {
          buffer.clear();
          if (_agentChatPopupWindow != null) {
            _agentChatPopupWindow!.invokeMethod('append_stream_chunk', {
              'text': chunk,
            }).catchError((_) {});
          }
        }
      });

      await for (final token in stream) {
        fullReply.write(token);
        buffer.write(token);
      }
    } on AgentException catch (e) {
      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('stream_error', {
            'error': e.message,
          });
        } catch (_) {}
      }
      return;
    } finally {
      flushTimer?.cancel();
      // 等待最后一次 timer 回调完成
      await Future.delayed(const Duration(milliseconds: 120));
      // 清空残留
      final remaining = buffer.toString();
      if (remaining.isNotEmpty && _agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('append_stream_chunk', {
            'text': remaining,
          });
        } catch (_) {}
      }
    }

    // 写入历史
    final reply = fullReply.toString();
    if (reply.isNotEmpty) {
      messages.add({'role': 'assistant', 'content': reply});
      _agentConversations[convId] = messages;

      // 持久化到磁盘
      final conv = ChatConversation(
        id: convId,
        title: text.length > 20 ? '${text.substring(0, 20)}...' : text,
        model: '',
        mode: mode,
        messages: messages,
      );
      await ChatStorageService.save(conv);

      // 更新对话标题
      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('update_conversation_title', {
            'id': convId,
            'title': conv.title,
          });
        } catch (_) {}
      }
    }

    // 通知流结束
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('stream_end');
      } catch (_) {}
    }
  }

  Future<void> _regenerateAgentReply() async {
    if (_activeConversationId == null) return;

    final convId = _activeConversationId!;
    final messages = _agentConversations[convId] ?? [];

    if (messages.isNotEmpty && messages.last['role'] == 'assistant') {
      messages.removeLast();
    }
    final userIndex = messages.lastIndexWhere(
      (m) => m['role'] == 'user',
    );
    if (userIndex == -1) return;
    final userText = messages[userIndex]['content'] ?? '';

    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('remove_last_message');
      } catch (_) {}
    }

    final fullReply = StringBuffer();
    final buffer = StringBuffer();
    Timer? flushTimer;

    try {
      final stream = AgentService.chatStream(
        userText,
        history: messages.sublist(0, userIndex),
      );

      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('add_message', {
            'text': '',
            'isUser': false,
            'streaming': true,
          });
        } catch (_) {}
      }

      flushTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        final chunk = buffer.toString();
        if (chunk.isNotEmpty) {
          buffer.clear();
          if (_agentChatPopupWindow != null) {
            _agentChatPopupWindow!.invokeMethod('append_stream_chunk', {
              'text': chunk,
            }).catchError((_) {});
          }
        }
      });

      await for (final token in stream) {
        fullReply.write(token);
        buffer.write(token);
      }
    } on AgentException catch (e) {
      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('stream_error', {
            'error': e.message,
          });
        } catch (_) {}
      }
      return;
    } finally {
      flushTimer?.cancel();
      await Future.delayed(const Duration(milliseconds: 120));
      final remaining = buffer.toString();
      if (remaining.isNotEmpty && _agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('append_stream_chunk', {
            'text': remaining,
          });
        } catch (_) {}
      }
    }

    final reply = fullReply.toString();
    if (reply.isNotEmpty) {
      messages.add({'role': 'assistant', 'content': reply});
      _agentConversations[convId] = messages;

      // 持久化到磁盘
      final conv = ChatConversation(
        id: convId,
        title: userText.length > 20 ? '${userText.substring(0, 20)}...' : userText,
        model: '',
        mode: 'accept',
        messages: messages,
      );
      await ChatStorageService.save(conv);
    }

    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('stream_end');
      } catch (_) {}
    }
  }

  // ─── 抽屉显隐 ──────────────────────────────────────────────────────────────

  /// 鼠标位置监控：检测是否进入触发区域
  void _startMouseMonitor() {
    _mouseMonitorTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _checkMousePosition(),
    );
  }

  Future<void> _checkMousePosition() async {
    if (_drawerAnimating) return;
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      final display = await screenRetriever.getPrimaryDisplay();
      final screenSize = display.visibleSize ?? display.size;
      _screenWidth = screenSize.width;

      // 触发区域：屏幕顶部中央
      final triggerLeft = (screenSize.width - _triggerZoneWidth) / 2;
      final triggerRect = Rect.fromLTWH(
        triggerLeft, 0, _triggerZoneWidth, _triggerZoneHeight,
      );
      final inTrigger = triggerRect.contains(cursor);

      // 当前宠物窗口区域
      final petLeft = (screenSize.width - PetConfig.windowWidth) / 2;
      final petRect = _drawerShown
          ? Rect.fromLTWH(petLeft, 10, PetConfig.windowWidth, PetConfig.windowHeight)
          : Rect.fromLTWH(petLeft, -PetConfig.windowHeight, PetConfig.windowWidth, PetConfig.windowHeight);
      final inPet = petRect.contains(cursor);

      if (inTrigger && !_drawerShown) {
        _showDrawer();
      } else if (inPet && _drawerShown) {
        _resetHideTimer();
      } else if (!inTrigger && !inPet && _drawerShown && _hideTimer == null) {
        _startHideTimer();
      }
    } catch (_) {}
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(milliseconds: (_autoHideDelay * 1000).round()), () {
      _hideTimer = null;
      _hideDrawer();
    });
  }

  Future<void> _toggleDrawer() async {
    if (_drawerShown) {
      _hideDrawer();
    } else {
      _showDrawer();
    }
  }

  Future<void> _showDrawer() async {
    if (_drawerShown || _drawerAnimating) return;
    _drawerAnimating = true;
    _resetHideTimer();

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    _screenWidth = screenSize.width;
    final centerX = (screenSize.width - PetConfig.windowWidth) / 2;

    const startY = -PetConfig.windowHeight;
    const endY = 10.0;
    const totalFrames = 15;

    for (var frame = 0; frame <= totalFrames; frame++) {
      final progress = frame / totalFrames;
      // ease-out quad
      final eased = 1 - (1 - progress) * (1 - progress);
      final currentY = startY + (endY - startY) * eased;
      try {
        await windowManager.setPosition(Offset(centerX, currentY));
      } catch (_) {}
      if (frame < totalFrames) {
        await Future.delayed(const Duration(milliseconds: 16));
      }
    }

    _drawerShown = true;
    _drawerAnimating = false;
    _startHideTimer();
  }

  Future<void> _hideDrawer() async {
    if (!_drawerShown || _drawerAnimating) return;
    _drawerAnimating = true;
    _resetHideTimer();

    final centerX = (_screenWidth - PetConfig.windowWidth) / 2;

    const startY = 10.0;
    const endY = -PetConfig.windowHeight;
    const totalFrames = 12;

    for (var frame = 0; frame <= totalFrames; frame++) {
      final progress = frame / totalFrames;
      final eased = 1 - (1 - progress) * (1 - progress);
      final currentY = startY + (endY - startY) * eased;
      try {
        await windowManager.setPosition(Offset(centerX, currentY));
      } catch (_) {}
      if (frame < totalFrames) {
        await Future.delayed(const Duration(milliseconds: 16));
      }
    }

    _drawerShown = false;
    _drawerAnimating = false;
  }

  /// 打开 MenuScreen 窗口（右侧面板）
  Future<void> _showMenuWindow() async {
    _menuVisible = true;

    final screenBounds = await _getScreenBounds();
    final menuBounds = Rect.fromLTWH(
      screenBounds.right - _menuWidth,
      screenBounds.top,
      _menuWidth,
      screenBounds.height,
    );

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
    }
  }

  /// 切换 MenuScreen 显隐
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

  // ─── Agent 弹窗显隐 ────────────────────────────────────────────────────────

  Future<void> _toggleAgentChatPopup() async {
    if (!_agentPopupVisible || _agentPopupMinimized) {
      // 未打开或已最小化 → 打开/恢复
      if (_agentPopupMinimized) {
        // 恢复最小化的窗口
        if (_agentChatPopupWindow != null) {
          try {
            await _agentChatPopupWindow!.invokeMethod('restore_window');
          } catch (_) {}
        }
        _agentPopupMinimized = false;
      } else {
        await _showAgentChatPopup();
      }
      _agentPopupFocused = true;
    } else if (!_agentPopupFocused) {
      // 已打开但未置顶 → 置顶
      if (_agentChatPopupWindow != null) {
        try {
          await _agentChatPopupWindow!.invokeMethod('focus_window');
        } catch (_) {}
      }
      _agentPopupFocused = true;
    } else {
      // 已打开且置顶 → 关闭（隐藏）
      await _hideAgentChatPopup();
    }
  }

  Future<void> _showAgentChatPopup() async {
    _agentPopupVisible = true;

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.visibleSize ?? display.size;
    final left = (screenSize.width - _agentChatPopupWidth) / 2;
    final top = (screenSize.height - _agentChatPopupHeight) / 2;

    final settings = await SettingsService.load();
    final popupTheme = settings.agentChatPopupTheme;
    final model = settings.model.isEmpty
        ? PlatformConfig.defaultChatModel(settings.platform)
        : settings.model;

    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.invokeMethod('set_data', {
          'left': left,
          'top': top,
          'width': _agentChatPopupWidth,
          'height': _agentChatPopupHeight,
          'theme': popupTheme,
          'model': model,
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
          'left': left,
          'top': top,
          'width': _agentChatPopupWidth,
          'height': _agentChatPopupHeight,
          'theme': popupTheme,
          'model': model,
        }),
      ),
    );
    _agentChatPopupWindow = createdWindow;
  }

  Future<void> _hideAgentChatPopup() async {
    _agentPopupVisible = false;
    _agentPopupFocused = false;
    _agentPopupMinimized = false;
    if (_agentChatPopupWindow != null) {
      try {
        await _agentChatPopupWindow!.hide();
      } catch (_) {
        _agentChatPopupWindow = null;
      }
    }
  }

  // ─── 各子窗口 ──────────────────────────────────────────────────────────────

  Future<void> _showSettings() async {
    try {
      await _settingsWindow?.hide();
    } catch (_) {}
    _settingsWindow = null;

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
    // 预创建菜单窗口（右侧固定位置）
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

    // 预创建笔记编辑弹窗
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

    // 预创建 agent 消息弹窗（居中）
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final screenSize = display.visibleSize ?? display.size;
      final left = (screenSize.width - _agentChatPopupWidth) / 2;
      final top = (screenSize.height - _agentChatPopupHeight) / 2;
      final settings = await SettingsService.load();
      final model = settings.model.isEmpty
          ? PlatformConfig.defaultChatModel(settings.platform)
          : settings.model;
      _agentChatPopupWindow = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'agent_chat_popup',
            'hidden': true,
            'left': left,
            'top': top,
            'width': _agentChatPopupWidth,
            'height': _agentChatPopupHeight,
            'model': model,
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
        _toggleMenuWindow();
        return;
      case 'open_settings':
        _showSettings();
        return;
      case 'toggle_agent':
        _toggleAgentChatPopup();
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
    final screenBounds = await _getScreenBounds();
    // 弹窗定位在 menu（屏幕右边缘，宽 _menuWidth）左侧，留 8px 间距
    final popupLeft = (screenBounds.right - _menuWidth - _todoItemPopupWidth - 8)
        .clamp(0.0, screenBounds.right - _todoItemPopupWidth);
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

  // ─── 构建 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _PetBody(
      petStyle: _petStyle,
      onToggleMenu: _toggleMenuWindow,
      onToggleAgent: _toggleAgentChatPopup,
      onToggleSettings: _showSettings,
    );
  }
}

class _PetBody extends StatefulWidget {
  const _PetBody({
    required this.petStyle,
    required this.onToggleMenu,
    required this.onToggleAgent,
    required this.onToggleSettings,
  });

  final String petStyle;
  final VoidCallback onToggleMenu;
  final VoidCallback onToggleAgent;
  final VoidCallback onToggleSettings;

  @override
  State<_PetBody> createState() => _PetBodyState();
}

class _PetBodyState extends State<_PetBody> {
  bool _ballHovered = false;
  bool _terminalHovered = false;
  bool _settingsHovered = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(PetConfig.windowRadius),
        child: Container(
          color: const Color(0xDB393939),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 悬浮球
            GestureDetector(
              onTap: widget.onToggleMenu,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _ballHovered = true),
                onExit: (_) => setState(() => _ballHovered = false),
                child: AnimatedScale(
                  scale: _ballHovered ? 1.15 : 1.0,
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
            const SizedBox(width: 6),
            const SizedBox(width: 6),
            // 终端按钮
            GestureDetector(
              onTap: widget.onToggleAgent,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _terminalHovered = true),
                onExit: (_) => setState(() => _terminalHovered = false),
                child: AnimatedScale(
                  scale: _terminalHovered ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/svg/cli.svg',
                        width: 23,
                        height: 23,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFFFFFFFF),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 设置按钮
            GestureDetector(
              onTap: widget.onToggleSettings,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _settingsHovered = true),
                onExit: (_) => setState(() => _settingsHovered = false),
                child: AnimatedScale(
                  scale: _settingsHovered ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: SizedBox(
                    width: 40,
                    height: 30,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/svg/设置.svg',
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFFFFFFFF),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
