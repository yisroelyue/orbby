import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/app_square_panel.dart';

class AppBarScreen extends StatefulWidget {
  const AppBarScreen({super.key});

  @override
  State<AppBarScreen> createState() => _AppBarScreenState();
}

class _AppBarScreenState extends State<AppBarScreen> with WindowListener {
  static const _events = WindowMethodChannel(
    'orbby_app_bar_events',
    mode: ChannelMode.unidirectional,
  );
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowBlur() {
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
          color: const Color(0xFFFFFFFF),
          child: const AppSquarePanel(),
        ),
      ),
    );
  }
}
