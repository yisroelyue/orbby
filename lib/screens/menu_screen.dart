import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/constants.dart';
import '../config/settings.dart';
import '../widgets/app_square_panel.dart';
import '../widgets/balance_panel.dart';
import '../widgets/control_panel.dart';
import '../widgets/daily_quote_panel.dart';
import '../widgets/favorites_panel.dart';
import '../widgets/frosted_panel.dart';
import '../widgets/interactive_icon.dart';
import '../widgets/news_panel.dart';
import '../widgets/photo_wall_panel.dart';
import '../widgets/schedule_panel.dart';
import '../widgets/script_panel.dart';
import '../widgets/todo_panel.dart';
import '../widgets/translate_panel.dart';
import '../widgets/weather_panel.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  static const menuChannel = WindowMethodChannel(
    'orbby_menu_events',
    mode: ChannelMode.unidirectional,
  );

  /// 外部触发余额刷新
  static final refreshNotifier = ValueNotifier<int>(0);
  static void triggerRefresh() => refreshNotifier.value++;

  /// 仅刷新笔记，不触发余额请求
  static final todoRefreshNotifier = ValueNotifier<int>(0);
  static void triggerTodoRefresh() => todoRefreshNotifier.value++;

  /// 刷新收藏面板
  static final favoritesRefreshNotifier = ValueNotifier<int>(0);
  static void triggerFavoritesRefresh() => favoritesRefreshNotifier.value++;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool _photoWallHidden = false;
  bool _balanceHidden = false;
  bool _translateHidden = false;
  bool _todoHidden = false;
  bool _favoritesHidden = false;
  bool _appsHidden = false;
  bool _controlHidden = false;
  bool _weatherHidden = false;
  bool _newsHidden = false;
  bool _scriptHidden = false;
  bool _scheduleHidden = false;
  bool _dailyQuoteHidden = false;
  Color _menuBgColor = const Color(0xFFA1A1A1);
  bool _isDark = true;
  String _userName = '';
  String _userAvatarPath = '';
  String _menuBgImage = '';

  Color get _iconColor => _isDark ? Colors.white : const Color(0xFF555555);
  Color get _textColor => _isDark ? Colors.white : const Color(0xFF333333);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    MenuScreen.refreshNotifier.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    MenuScreen.refreshNotifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    _loadSettings();
  }

  Future<void> _toggleTheme() async {
    final s = await SettingsService.load();
    s.appTheme = _isDark ? 'light' : 'dark';
    await SettingsService.save(s);
    MenuScreen.triggerRefresh();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _photoWallHidden = !s.showPhotoWallPanel;
      _balanceHidden = !s.showBalancePanel;
      _translateHidden = !s.showTranslatePanel;
      _todoHidden = !s.showTodoPanel;
      _favoritesHidden = !s.showFavoritesPanel;
      _appsHidden = !s.showAppSquarePanel;
      _controlHidden = !s.showControlPanel;
      _weatherHidden = !s.showWeatherPanel;
      _newsHidden = !s.showNewsPanel;
      _scriptHidden = !s.showScriptPanel;
      _scheduleHidden = !s.showSchedulePanel;
      _dailyQuoteHidden = !s.showDailyQuotePanel;
      _isDark = s.appTheme == 'dark';
      _userName = s.userName;
      _userAvatarPath = s.userAvatarPath;
      _menuBgImage = s.menuBgImage;
      _menuBgColor = _isDark
          ? const Color(0xFF454545)
          : const Color(0xFFDCE3E3);
    });
  }

  void _openPanelDetail(String key) {
    switch (key) {
      case 'todo':
        MenuScreen.menuChannel.invokeMethod('open_todo_editor', {
          'id': '',
          'title': '',
        });
      case 'favorites':
        MenuScreen.menuChannel.invokeMethod('open_favorites_editor', {
          'folderId': '',
        });
      case 'apps':
        MenuScreen.menuChannel.invokeMethod('open_app_center');
    }
  }

  Future<void> _showPanel(String key) async {
    final s = await SettingsService.load();
    switch (key) {
      case 'photo_wall':
        s.showPhotoWallPanel = true;
      case 'balance':
        s.showBalancePanel = true;
      case 'translate':
        s.showTranslatePanel = true;
      case 'control':
        s.showControlPanel = true;
      case 'weather':
        s.showWeatherPanel = true;
      case 'news':
        s.showNewsPanel = true;
      case 'script':
        s.showScriptPanel = true;
      case 'schedule':
        s.showSchedulePanel = true;
      case 'daily_quote':
        s.showDailyQuotePanel = true;
    }
    await SettingsService.save(s);
    MenuScreen.triggerRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Microsoft YaHei'),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FrostedPanel(
              color: _menuBgColor,
              child: Stack(
                children: [
                  // 底层：全屏图片背景
                  if (_menuBgImage.isNotEmpty)
                    Positioned.fill(
                      child: Image.asset(
                        _menuBgImage,
                        fit: BoxFit.fitHeight,
                        alignment: Alignment.center,
                      ),
                    ),
                  // 上层：原有内容
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        // 顶行
                        _buildTopRow(),
                        // 面板区域
                        Expanded(child: _buildPanelList()),
                        // 底部功能按钮
                        _buildBottomRow(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    final hasUserInfo = _userName.isNotEmpty ||
        (_userAvatarPath.isNotEmpty && File(_userAvatarPath).existsSync());
    const topTextColor = Colors.white;
    const topIconColor = Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasUserInfo) ...[
            const SizedBox(width: 4),
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              backgroundImage: _userAvatarPath.isNotEmpty && File(_userAvatarPath).existsSync()
                  ? FileImage(File(_userAvatarPath))
                  : null,
              child: _userAvatarPath.isEmpty || !File(_userAvatarPath).existsSync()
                  ? const Icon(Icons.person, size: 22, color: Colors.white70)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _userName,
                style: const TextStyle(color: topTextColor, fontSize: 19, fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const SizedBox(width: 4),
            Image.asset(PetConfig.logoSprite, width: 32, height: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Orbby Assistant',
                style: const TextStyle(color: topTextColor, fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
          ],
          InteractiveIcon(
            size: 32,
            onTap: _toggleTheme,
            child: Icon(
              _isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: topIconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 6),
          InteractiveIcon(
            onTap: () => MenuScreen.menuChannel.invokeMethod('open_settings'),
            child: SvgPicture.asset(
              'assets/svg/设置.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                topIconColor,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InteractiveIcon(
            size: 32,
            onTap: () => MenuScreen.menuChannel.invokeMethod('close_menu'),
            child: const Icon(
              Icons.close_rounded,
              color: topIconColor,
              size: 20,
            ),
          ),
          ],
        ),
    );
  }

  Widget _buildPanelList() {
    return Theme(
      data: ThemeData(
        scrollbarTheme: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(0),
        ),
      ),
      child: ListView.separated(
      primary: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: 12,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        if (index == 0) {
          return const DailyQuotePanel();
        }
        if (index == 1) {
          return const PhotoWallPanel();
        }
        if (index == 2) {
          return const BalancePanel();
        }
        if (index == 3) {
          return const TranslatePanel();
        }
        if (index == 4) {
          return const WeatherPanel();
        }
        if (index == 5) {
          return const NewsPanel();
        }
        if (index == 6) {
          return const SchedulePanel();
        }
        if (index == 7) {
          return const ScriptPanel();
        }
        if (index == 8) {
          return const TodoPanel();
        }
        if (index == 9) {
          return const FavoritesPanel();
        }
        if (index == 10) {
          return const AppSquarePanel();
        }
        return const ControlPanel();
      },
      ),
    );
  }

  Widget _buildBottomRow() {
    final hiddenIcons = <Widget>[];

    if (_photoWallHidden) {
      hiddenIcons.add(_buildPanelActionIcon('photo_wall', Icons.photo_library_rounded, () => _showPanel('photo_wall')));
    }
    if (_balanceHidden) {
      hiddenIcons.add(_buildPanelActionIcon('balance', Icons.account_balance_wallet_rounded, () => _showPanel('balance')));
    }
    if (_translateHidden) {
      hiddenIcons.add(_buildPanelActionIcon('translate', Icons.translate_rounded, () => _showPanel('translate')));
    }
    if (_todoHidden) {
      hiddenIcons.add(_buildPanelToggleSvg('todo', 'assets/svg/笔记.svg'));
    }
    if (_favoritesHidden) {
      hiddenIcons.add(_buildPanelToggleSvg('favorites', 'assets/svg/收藏.svg'));
    }
    if (_appsHidden) {
      hiddenIcons.add(_buildPanelToggleSvg('apps', 'assets/svg/应用.svg'));
    }
    if (_controlHidden) {
      hiddenIcons.add(_buildPanelActionIcon('control', Icons.tune_rounded, () => _showPanel('control')));
    }
    if (_weatherHidden) {
      hiddenIcons.add(_buildPanelActionIcon('weather', Icons.cloud_rounded, () => _showPanel('weather')));
    }
    if (_newsHidden) {
      hiddenIcons.add(_buildPanelActionIcon('news', Icons.newspaper_rounded, () => _showPanel('news')));
    }
    if (_scriptHidden) {
      hiddenIcons.add(_buildPanelActionIcon('script', Icons.code_rounded, () => _showPanel('script')));
    }
    if (_scheduleHidden) {
      hiddenIcons.add(_buildPanelActionIcon('schedule', Icons.calendar_today_rounded, () => _showPanel('schedule')));
    }
    if (_dailyQuoteHidden) {
      hiddenIcons.add(_buildPanelActionIcon('daily_quote', Icons.format_quote_rounded, () => _showPanel('daily_quote')));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          InteractiveIcon(
            size: 36,
            onTap: _openClaudeTerminal,
            child: Icon(
              Icons.terminal_rounded,
              color: _iconColor,
              size: 22,
            ),
          ),
          ...hiddenIcons,
        ],
      ),
    );
  }

  Widget _buildPanelToggleIcon(String key, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InteractiveIcon(
        size: 32,
        onTap: () => _openPanelDetail(key),
        child: Icon(icon, color: _iconColor, size: 20),
      ),
    );
  }

  Widget _buildPanelActionIcon(String key, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InteractiveIcon(
        size: 32,
        onTap: onTap,
        child: Icon(icon, color: _iconColor, size: 20),
      ),
    );
  }

  Widget _buildPanelToggleSvg(String key, String assetPath) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InteractiveIcon(
        size: 32,
        onTap: () => _openPanelDetail(key),
        child: SvgPicture.asset(
          assetPath,
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(
            _iconColor,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  void _openClaudeTerminal() {
    if (Platform.isWindows) {
      Process.start('cmd', ['/c', 'start', 'cmd', '/k', 'claude'],
        mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      Process.start('osascript', [
        '-e', 'tell application "Terminal" to do script "claude"',
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      Process.start('x-terminal-emulator', ['-e', 'bash -c "claude; exec bash"'],
        mode: ProcessStartMode.detached);
    }
  }
}
