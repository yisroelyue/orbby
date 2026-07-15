import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/constants.dart';
import '../config/settings.dart';
import '../widgets/app_square_panel.dart';
import '../widgets/balance_panel.dart';
import '../widgets/favorites_panel.dart';
import '../widgets/frosted_panel.dart';
import '../widgets/interactive_icon.dart';
import '../widgets/photo_wall_panel.dart';
import '../widgets/todo_panel.dart';
import '../widgets/translate_panel.dart';

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
  Color _menuBgColor = const Color(0x77A1A1A1);
  bool _isDark = true;
  String _userName = '';
  String _userAvatarPath = '';

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
      _isDark = s.appTheme == 'dark';
      _userName = s.userName;
      _userAvatarPath = s.userAvatarPath;
      _menuBgColor = _isDark
          ? const Color(0x77A1A1A1)
          : const Color(0x88E8E8E8);
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
    }
    await SettingsService.save(s);
    MenuScreen.triggerRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'NotoSansSC'),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: FrostedPanel(
          color: _menuBgColor,
          child: Padding(
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
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    final hasUserInfo = _userName.isNotEmpty ||
        (_userAvatarPath.isNotEmpty && File(_userAvatarPath).existsSync());
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
                  ? Icon(Icons.person, size: 22, color: _iconColor.withValues(alpha: 0.6))
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _userName,
                style: TextStyle(color: _textColor, fontSize: 19, fontWeight: FontWeight.w800),
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
                style: TextStyle(color: _textColor, fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
          ],
          InteractiveIcon(
            size: 32,
            onTap: _toggleTheme,
            child: Icon(
              _isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: _iconColor,
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
              colorFilter: ColorFilter.mode(
                _iconColor,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InteractiveIcon(
            size: 32,
            onTap: () => MenuScreen.menuChannel.invokeMethod('close_menu'),
            child: Icon(
              Icons.close_rounded,
              color: _iconColor,
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
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        if (index == 0) {
          return const PhotoWallPanel();
        }
        if (index == 1) {
          return const BalancePanel();
        }
        if (index == 2) {
          return const TranslatePanel();
        }
        if (index == 3) {
          return const TodoPanel();
        }
        if (index == 4) {
          return const FavoritesPanel();
        }
        return const AppSquarePanel();
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
