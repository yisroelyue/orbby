import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/app_square_panel.dart';

class AppBarScreen extends StatefulWidget {
  const AppBarScreen({super.key});
  static final refreshNotifier = ValueNotifier<int>(0);

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
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    AppBarScreen.refreshNotifier.addListener(_refresh);
    // 通知主窗口：Flutter engine、MethodChannel 和首屏状态均已准备完成。
    _events.invokeMethod('ready');
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    AppBarScreen.refreshNotifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  void onWindowBlur() {
    _hideOnBlur();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wasFocused = true;
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: const Color(0xFFCACACA),
          child: AppSquarePanel(key: ValueKey(AppBarScreen.refreshNotifier.value)),
        ),
      ),
    );
  }
}
