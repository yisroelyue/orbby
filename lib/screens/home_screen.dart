import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../widgets/frosted_panel.dart';
import 'tab/agent_chat_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const menuChannel = WindowMethodChannel(
    'orbby_menu_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// 缓存避免每次 build 重建 ThemeData 触发全树刷新
  static final _theme = ThemeData(
    fontFamily: 'Microsoft YaHei',
    scaffoldBackgroundColor: Colors.grey,
  );

  /// 面板深灰黑背景（比聊天区 0xFF1E1E1E 略亮，形成分层）
  static const _panelBg = Color(0xFF252526);

  /// 菜单窗口是否曾获得焦点（用于失焦自动隐藏）
  bool _wasFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeScreen.menuChannel.invokeMethod('ready');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wasFocused = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 菜单已获得过焦点再失焦时，自动隐藏
        if (_wasFocused) {
          _wasFocused = false;
          HomeScreen.menuChannel.invokeMethod('close_menu');
        }
        break;
      default:
        break;
    }
  }

  // =========================================================================
  // Build
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(-10, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FrostedPanel(
              color: _panelBg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 25),
                child: const AgentChatTab(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
