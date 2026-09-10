import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/interactive_icon.dart';
import 'settings_view.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const eventsChannel = WindowMethodChannel(
    'orbby_settings_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // 通知主窗口：Flutter engine 与 handler 均已就绪，可以 place 显示。
    SettingsScreen.eventsChannel.invokeMethod('ready');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: const Color(0xFFF5F5F5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onPanStart: (_) => windowManager.startDragging(),
                    child: Row(
                      children: [
                        SvgPicture.asset('assets/svg/setting.svg',
                            width: 22, height: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '设置',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        InteractiveIcon(
                          size: 30,
                          onTap: () {
                            SettingsScreen.eventsChannel.invokeMethod('hidden');
                            windowManager.hide();
                          },
                          child: const Icon(Icons.close,
                              color: Colors.black38, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Expanded(child: SettingsView()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
