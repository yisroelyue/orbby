import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../config/constants.dart';
import '../config/settings.dart';
import '../services/weixin/weixin_models.dart';
import '../widgets/frosted_panel.dart';
import '../widgets/interactive_icon.dart';
import 'tab/agent_chat_tab.dart';
import 'tab/settings_tab.dart';

// ---------------------------------------------------------------------------
// 数据模型
// ---------------------------------------------------------------------------

/// Tab 页描述，驱动 tab 按钮和内容
class HomeTab {
  const HomeTab({required this.svgName, this.builder, this.onTap});

  /// SVG 图标的基础名称（不含扩展名），对应 assets/svg/home-tab/ 下的文件。
  /// 非激活态使用 `$svgName.svg`，激活态使用 `$svgName-c.svg`。
  final String svgName;
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

  /// 微信服务由主窗口唯一持有；菜单窗口仅保存主窗口推送的状态快照。
  static final weixinStatusNotifier = ValueNotifier(
    const WeixinServiceStatus(),
  );

  static void applyWeixinStatus(Object? raw) {
    if (raw is! Map) return;
    weixinStatusNotifier.value = WeixinServiceStatus.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }

  static Future<WeixinServiceStatus> queryWeixinStatus() async {
    final raw = await menuChannel.invokeMethod('weixin_get_status');
    applyWeixinStatus(raw);
    return weixinStatusNotifier.value;
  }

  static Future<WeixinServiceStatus> setWeixinEnabled(bool enabled) async {
    final raw = await menuChannel.invokeMethod('weixin_set_enabled', {
      'enabled': enabled,
    });
    applyWeixinStatus(raw);
    return weixinStatusNotifier.value;
  }

  static Future<WeixinServiceStatus> bindWeixinAccount(
    ClawBotAccount account,
  ) async {
    final raw = await menuChannel.invokeMethod(
      'weixin_bind_account',
      account.toJson(),
    );
    applyWeixinStatus(raw);
    return weixinStatusNotifier.value;
  }

  static Future<WeixinServiceStatus> logoutWeixin() async {
    final raw = await menuChannel.invokeMethod('weixin_logout');
    applyWeixinStatus(raw);
    return weixinStatusNotifier.value;
  }

  /// 设置变更通知器（面板开关等设置变化时触发）
  static final settingsChangeNotifier = ValueNotifier<int>(0);
  static void triggerSettingsChange() => settingsChangeNotifier.value++;

  /// Tab 切换通知器，value 为目标 tab 索引
  static final tabSwitchNotifier = ValueNotifier<int>(-1);
  static void triggerTabSwitch(int index) => tabSwitchNotifier.value = index;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isDark = true;
  int _currentTab = 0;

  /// 菜单窗口是否曾获得焦点（用于失焦自动隐藏）
  bool _wasFocused = false;

  // ---- Tab 定义 ----
  late final List<HomeTab> _tabs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = [
      HomeTab(
        svgName: 'agent',
        builder: (_) => AgentChatTab(isDark: _isDark),
      ),
      HomeTab(svgName: 'setting', builder: (_) => const SettingsTab()),
    ];
    _loadSettings();
    HomeScreen.settingsChangeNotifier.addListener(_onSettingsChanged);
    HomeScreen.tabSwitchNotifier.addListener(_onTabSwitch);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeScreen.settingsChangeNotifier.removeListener(_onSettingsChanged);
    HomeScreen.tabSwitchNotifier.removeListener(_onTabSwitch);
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

  void _onSettingsChanged() => _loadSettings();

  void _onTabSwitch() {
    final index = HomeScreen.tabSwitchNotifier.value;
    if (index >= 0 && index < _tabs.length) {
      setState(() => _currentTab = index);
    }
  }

  Future<void> _loadSettings() async {
    final s = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _isDark = s.appTheme == 'dark';
    });
  }

  // =========================================================================
  // Build
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Microsoft YaHei',
        scaffoldBackgroundColor: Colors.grey,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: DragToResizeArea(
          enableResizeEdges: [ResizeEdge.top, ResizeEdge.bottom],
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FrostedPanel(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Column(
                  children: [
                    DragToMoveArea(
                      child: Row(
                        children: [
                          Expanded(child: _buildTopRow()),
                          _buildTabBar(),
                        ],
                      ),
                    ),
                    Expanded(child: _buildTabContent()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Top Row ----

  Widget _buildTopRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 4),
          Image.asset(PetConfig.logoSprite, width: 32, height: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Orbby Assistant',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Tab Bar ----

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.only(left: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            _buildTabButton(i, _tabs[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, HomeTab tab) {
    final isActive = _currentTab == index;
    final svgAsset = isActive
        ? 'assets/svg/home-tab/${tab.svgName}-c.svg'
        : 'assets/svg/home-tab/${tab.svgName}.svg';
    return GestureDetector(
      onTap: () {
        if (tab.onTap != null) {
          tab.onTap!();
        } else {
          setState(() => _currentTab = index);
        }
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? Colors.black.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: EdgeInsets.all(isActive ? 6 : 8),
          child: SvgPicture.asset(
            svgAsset,
            width: isActive ? 24 : 20,
            height: isActive ? 24 : 20,
          ),
        ),
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
