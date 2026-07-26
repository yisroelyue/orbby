import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/constants.dart';
import '../config/settings.dart';
import '../widgets/frosted_panel.dart';
import '../widgets/interactive_icon.dart';
import 'tab/agent_chat_tab.dart';
import 'tab/dashboard_tab.dart';
import 'tab/settings_tab.dart';

// ---------------------------------------------------------------------------
// 数据模型
// ---------------------------------------------------------------------------

/// Tab 页描述，驱动 tab 按钮和内容
class HomeTab {
  const HomeTab({
    required this.icon,
    this.builder,
    this.onTap,
  });

  final IconData icon;
  final WidgetBuilder? builder;

  /// 非 null 时点击触发外部动作（如打开设置窗口），不切换 tab
  final VoidCallback? onTap;
}

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const menuChannel = WindowMethodChannel(
    'orbby_menu_events',
    mode: ChannelMode.unidirectional,
  );

  static final refreshNotifier = ValueNotifier<int>(0);
  static void triggerRefresh() => refreshNotifier.value++;

  /// 主题变更通知器，仅用于通知主题颜色变化
  static final themeNotifier = ValueNotifier<int>(0);
  static void triggerThemeChange() => themeNotifier.value++;

  static final todoRefreshNotifier = ValueNotifier<int>(0);
  static void triggerTodoRefresh() => todoRefreshNotifier.value++;

  /// 面板顺序变更通知器
  static final panelOrderNotifier = ValueNotifier<int>(0);
  static void triggerPanelOrderChange() => panelOrderNotifier.value++;

  /// 编辑布局模式通知器
  static final editModeNotifier = ValueNotifier<bool>(false);
  static void toggleEditMode() => editModeNotifier.value = !editModeNotifier.value;

  /// 设置变更通知器（面板开关等设置变化时触发）
  static final settingsChangeNotifier = ValueNotifier<int>(0);
  static void triggerSettingsChange() => settingsChangeNotifier.value++;

  static final favoritesRefreshNotifier = ValueNotifier<int>(0);
  static void triggerFavoritesRefresh() => favoritesRefreshNotifier.value++;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Color _menuBgColor = const Color(0xFFA1A1A1);
  bool _isDark = true;
  String _userName = '';
  String _userAvatarPath = '';
  String _menuBgImage = '';
  int _currentTab = 0;

  // ---- Tab 定义 ----
  late final List<HomeTab> _tabs;

  static const _settingsChannel = WindowMethodChannel(
    'orbby_settings_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  void initState() {
    super.initState();
    _settingsChannel.setMethodCallHandler(_onSettingsSaved);
    _tabs = [
      HomeTab(
        icon: Icons.dashboard_rounded,
        builder: (_) => const DashboardTab(),
      ),
      HomeTab(
        icon: Icons.smart_toy_rounded,
        builder: (_) => AgentChatTab(isDark: _isDark),
      ),
      HomeTab(
        icon: Icons.settings_rounded,
        builder: (_) => const SettingsTab(),
      ),
    ];
    _loadSettings();
    HomeScreen.themeNotifier.addListener(_onSettingsChanged);
    HomeScreen.settingsChangeNotifier.addListener(_onSettingsChanged);
    HomeScreen.editModeNotifier.addListener(_onEditModeChanged);
  }

  @override
  void dispose() {
    _settingsChannel.setMethodCallHandler(null);
    HomeScreen.themeNotifier.removeListener(_onSettingsChanged);
    HomeScreen.settingsChangeNotifier.removeListener(_onSettingsChanged);
    HomeScreen.editModeNotifier.removeListener(_onEditModeChanged);
    super.dispose();
  }

  Future<void> _onSettingsSaved(MethodCall call) async {
    if (call.method == 'settings_saved') {
      HomeScreen.triggerSettingsChange();
      _loadSettings();
    }
  }

  void _onSettingsChanged() => _loadSettings();

  void _onEditModeChanged() => setState(() {});

  Future<void> _toggleTheme() async {
    final s = await SettingsService.load();
    s.appTheme = _isDark ? 'light' : 'dark';
    await SettingsService.save(s);
    HomeScreen.triggerThemeChange();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _isDark = s.appTheme == 'dark';
      _userName = s.userName;
      _userAvatarPath = s.userAvatarPath;
      _menuBgImage = s.menuBgImage;
      _menuBgColor = _isDark ? const Color(0xFF454545) : const Color(0xFFDCE3E3);
    });
  }

  // =========================================================================
  // Build
  // =========================================================================

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
                  if (_menuBgImage.isNotEmpty)
                    Positioned.fill(
                      child: Image.asset(
                        _menuBgImage,
                        key: ValueKey(_menuBgImage),
                        fit: BoxFit.fitHeight,
                        alignment: Alignment.center,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 12, bottom: 12, right: 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _buildTopRow(),
                              Expanded(child: _buildTabContent()),
                            ],
                          ),
                        ),
                        _buildTabBar(),
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

  // ---- Top Row ----

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
          ValueListenableBuilder<bool>(
            valueListenable: HomeScreen.editModeNotifier,
            builder: (_, editing, __) => InteractiveIcon(
              size: 32,
              onTap: HomeScreen.toggleEditMode,
              child: Icon(
                editing ? Icons.edit_off_rounded : Icons.edit_rounded,
                color: editing ? Colors.amber : topIconColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 6),
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
            onTap: () => HomeScreen.menuChannel.invokeMethod('open_settings'),
            child: SvgPicture.asset(
              'assets/svg/设置.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(topIconColor, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 6),
          InteractiveIcon(
            size: 32,
            onTap: () => HomeScreen.menuChannel.invokeMethod('close_menu'),
            child: const Icon(Icons.close_rounded, color: topIconColor, size: 20),
          ),
        ],
      ),
    );
  }

  // ---- Tab Bar ----

  Widget _buildTabBar() {
    return Container(
      width: 36,
      margin: const EdgeInsets.only(left: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildTabButton(i, _tabs[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, HomeTab tab) {
    final isActive = _currentTab == index;
    final activeColor = _isDark ? Colors.white : const Color(0xFF333333);
    final inactiveColor = _isDark ? Colors.white54 : Colors.black54;
    return GestureDetector(
      onTap: () {
        if (tab.onTap != null) {
          tab.onTap!();
        } else {
          setState(() => _currentTab = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive
              ? (_isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(tab.icon, size: 20, color: isActive ? activeColor : inactiveColor),
      ),
    );
  }

  // ---- Tab Content ----

  Widget _buildTabContent() {
    return IndexedStack(
      index: _currentTab,
      children: [
        for (final tab in _tabs)
          tab.builder != null ? tab.builder!(context) : const SizedBox.shrink(),
      ],
    );
  }
}
