import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/app_square_panel.dart';

class AppBarScreen extends StatefulWidget {
  const AppBarScreen({super.key});

  @override
  State<AppBarScreen> createState() => _AppBarScreenState();
}

class _AppBarScreenState extends State<AppBarScreen>
    with WindowListener, WidgetsBindingObserver {
  static const _events = WindowMethodChannel(
    'orbby_app_bar_events',
    mode: ChannelMode.unidirectional,
  );
  bool _wasFocused = false;
  final _escFocus = FocusNode();
  final _panelKey = GlobalKey<AppSquarePanelState>();
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    // 通知主窗口：Flutter engine、MethodChannel 和首屏状态均已准备完成。
    _events.invokeMethod('ready');
    // 面板是纯 GestureDetector 网格、无可聚焦控件，焦点链上没有节点，
    // 只挂 onKeyEvent 的外层 Focus 收不到键盘事件（content 窗口靠输入框
    // requestFocus 才生效）——由本节点主动持有焦点承载 Esc。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _escFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _escFocus.dispose();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowBlur() {
    _hideOnBlur();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wasFocused = true;
        // 常驻窗口 hide/show 后确保焦点仍在（防 native 时序丢焦点导致 Esc 失灵）。
        if (!_escFocus.hasFocus) _escFocus.requestFocus();
        // 键盘选中重置回首项（与 content 窗口 place 时重置 _selectedAction 同步）。
        _panelKey.currentState?.resetSelection();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_wasFocused) {
          _wasFocused = false;
          _hideOnBlur();
        }
        break;
      default:
        break;
    }
  }

  void _hideOnBlur() {
    _events.invokeMethod('hidden');
    windowManager.hide();
  }

  /// 键盘接管（与 content 窗口同一模式，见 content_screen.dart）：
  /// Esc 隐藏面板（复用失焦隐藏路径，通知 hub 同步 _appBarVisible）、
  /// ←/→ 循环移动选中、回车执行选中项。带修饰键的方向键不拦截：
  /// Shift+方向等编辑键不受影响。面板内无可聚焦控件，本节点自身持有焦点
  /// （见 initState），事件必然经过这里；skipTraversal 使其不参与 Tab 遍历，
  /// 鼠标点击 GestureDetector 图标也不受焦点影响。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _hideOnBlur();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final plainArrows = !keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed;
    if (plainArrows && key == LogicalKeyboardKey.arrowLeft) {
      _panelKey.currentState?.moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (plainArrows && key == LogicalKeyboardKey.arrowRight) {
      _panelKey.currentState?.moveSelection(1);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        !keyboard.isShiftPressed) {
      _panelKey.currentState?.runSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _escFocus,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: const Color(0xFFCACACA),
            child: AppSquarePanel(key: _panelKey),
          ),
        ),
      ),
    );
  }
}
