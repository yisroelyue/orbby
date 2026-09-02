import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orbby/services/log_service.dart';
import '../../config/platform.dart';
import '../../config/settings.dart';
import '../../services/agent_service.dart';
import '../../services/claude_hook_installer.dart';
import '../../services/translate_service.dart';
import '../../services/weixin/weixin_ilink_client.dart';
import '../../services/weixin/weixin_models.dart';
import '../../services/weixin/weixin_qr_login_widget.dart';
import '../../screens/home_screen.dart';
import '../../widgets/app_toast.dart';

enum _SettingCategory { display, panel, general, api, log }

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _detailScrollController = ScrollController();
  _SettingCategory _selected = _SettingCategory.general;

  late final TextEditingController _apiKeyController;
  late final TextEditingController _balanceUrlController;
  late final TextEditingController _chatUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _userNameController;
  late final TextEditingController _weatherApiIdController;
  late final TextEditingController _weatherApiKeyController;
  late final TextEditingController _weatherApiHostController;
  late final TextEditingController _weatherCityController;
  String _platform = 'deepseek';
  Map<String, PlatformApiConfig> _apiConfigs = {};
  bool _enableBalance = true;
  bool _obscureApiKey = true;
  bool _obscureWeatherApiKey = true;
  bool _autoStart = false;
  Map<String, LogCategoryConfig> _logCategories = {};
  String _language = 'zh';
  String _appTheme = 'light';
  String _petStyle = 'colorful';
  bool _claudeHookInstalled = false;
  bool _installingClaudeHooks = false;
  bool _loading = true;
  String _userName = '';
  String _userAvatarPath = '';
  bool _weixinConnected = false;
  bool _weixinConnecting = false;
  bool _weixinEnabled = false;
  WeixinConnectionState _weixinState = WeixinConnectionState.disconnected;
  String? _weixinError;
  String _weixinBotId = '';
  bool _weixinQrLoading = false;
  bool _weixinConnectLoading = false;
  VoidCallback? _connectionStateListener;
  String _menuBgImage = '';
  String _menuBgFilePath = '';
  String _dailyQuoteType = '';
  String _dailyQuoteCountry = '';
  int _balanceRefreshInterval = 0;
  int _photoWallSwitchInterval = 30;
  int _carouselSwitchInterval = 12;
  bool _showTranslateLangSelector = true;
  List<String> _translateEnabledLangs = [];

  /// 每日一言类型选项
  static const _dailyQuoteTypes = <String, String>{
    '': '不限',
    '诗词': '诗词',
    '名言': '名言',
    '歌词': '歌词',
    '歇后语': '歇后语',
    '俚语': '俚语',
    '短笑话': '短笑话',
  };

  /// 每日一言国家选项
  static const _dailyQuoteCountries = <String, String>{
    '': '不限',
    '中国': '中国',
    '外国': '外国',
  };

  /// 余额刷新频率选项（秒）
  static const _balanceRefreshIntervals = <int, String>{
    0: '每天',
    21600: '6小时',
    10800: '3小时',
  };

  /// 照片墙切换频率选项（秒）
  static const _photoWallSwitchIntervals = <int, String>{
    10: '10秒',
    30: '30秒',
    60: '1分钟',
    600: '10分钟',
    3600: '1小时',
  };

  /// 轮播图切换频率选项（秒）
  static const _carouselSwitchIntervals = <int, String>{
    5: '5秒',
    12: '12秒',
    30: '30秒',
    60: '1分钟',
    300: '5分钟',
  };

  /// 内置菜单背景图列表
  static const _menuBgOptions = <String>[
    '',
    'assets/png/menuBg/80939131.png',
    'assets/png/menuBg/55754261.png',
    'assets/png/menuBg/80039502.png',
  ];

  static const _categoryItems = <(_SettingCategory, IconData, String)>[
    (_SettingCategory.general, Icons.tune_rounded, '通用设置'),
    (_SettingCategory.api, Icons.smart_toy_outlined, '模型设置'),
    (_SettingCategory.log, Icons.article_outlined, '开发设置'),
  ];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _balanceUrlController = TextEditingController();
    _chatUrlController = TextEditingController();
    _modelController = TextEditingController();
    _userNameController = TextEditingController();
    _weatherApiIdController = TextEditingController();
    _weatherApiKeyController = TextEditingController();
    _weatherApiHostController = TextEditingController();
    _weatherCityController = TextEditingController();
    _loadSettings();

    // 微信服务由主窗口持有，监听其跨窗口状态快照。
    _connectionStateListener = () {
      if (!mounted) return;
      _applyWeixinStatus(HomeScreen.weixinStatusNotifier.value);
    };
    HomeScreen.weixinStatusNotifier.addListener(_connectionStateListener!);
  }

  Future<void> _loadSettings() async {
    final s = await SettingsService.load();
    final claudeHookInstalled =
        await ClaudeHookInstaller.isGlobalHookInstalled();
    if (!mounted) return;
    setState(() {
      _platform = s.platform;
      _apiConfigs = Map.of(s.apiConfigs);
      final cfg = s.currentApi;
      _apiKeyController.text = cfg.apiKey;
      _balanceUrlController.text = cfg.balanceUrl.isEmpty
          ? PlatformConfig.defaultBalanceUrl(s.platform)
          : cfg.balanceUrl;
      _chatUrlController.text = cfg.chatUrl.isEmpty
          ? PlatformConfig.defaultChatUrl(s.platform)
          : cfg.chatUrl;
      _modelController.text = cfg.model.isEmpty
          ? PlatformConfig.defaultChatModel(s.platform)
          : cfg.model;
      _enableBalance = cfg.enableBalance;
      _autoStart = s.autoStart;
      _logCategories = Map.of(s.logCategories);
      _language = s.language;
      _appTheme = s.appTheme;
      _petStyle = s.petStyle;
      _userName = s.userName;
      _userAvatarPath = s.userAvatarPath;
      _menuBgImage = s.menuBgImage;
      _menuBgFilePath = s.menuBgFilePath;
      _userNameController.text = s.userName;
      _weatherApiIdController.text = s.weatherApiId;
      _weatherApiKeyController.text = s.weatherApiKey;
      _weatherApiHostController.text = s.weatherApiHost;
      _weatherCityController.text = s.weatherCity;
      _dailyQuoteType = s.dailyQuoteType;
      _dailyQuoteCountry = s.dailyQuoteCountry;
      _balanceRefreshInterval = s.balanceRefreshInterval;
      _photoWallSwitchInterval = s.photoWallSwitchInterval;
      _carouselSwitchInterval = s.carouselSwitchInterval;
      _showTranslateLangSelector = s.showTranslateLangSelector;
      _translateEnabledLangs = List.of(s.translateEnabledLangs);
      _claudeHookInstalled = claudeHookInstalled;

      _loading = false;
    });

    try {
      final status = await HomeScreen.queryWeixinStatus();
      if (mounted) _applyWeixinStatus(status);
    } catch (e) {
      LogService.error('读取微信服务状态失败: $e', category: 'weixin');
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _balanceUrlController.dispose();
    _chatUrlController.dispose();
    _modelController.dispose();
    _userNameController.dispose();
    _weatherApiIdController.dispose();
    _weatherApiKeyController.dispose();
    _weatherApiHostController.dispose();
    _weatherCityController.dispose();
    _detailScrollController.dispose();
    if (_connectionStateListener != null) {
      HomeScreen.weixinStatusNotifier.removeListener(_connectionStateListener!);
    }
    super.dispose();
  }

  void _applyWeixinStatus(WeixinServiceStatus status) {
    if (!mounted) return;
    setState(() {
      _weixinState = status.state;
      _weixinEnabled = status.enabled;
      _weixinConnected = status.isConnected;
      _weixinConnecting = status.isConnecting;
      _weixinBotId = status.botId;
      _weixinError = status.error;
      if (!status.isConnecting) {
        _weixinConnectLoading = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildTopTabBar(),
          Expanded(child: _buildDetailPanel()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildTopTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _buildSegmented<_SettingCategory>(
        value: _selected,
        items: _categoryItems.map((e) => e.$1).toList(),
        labelBuilder: (cat) => _categoryItems.firstWhere((e) => e.$1 == cat).$3,
        onChanged: (v) => setState(() => _selected = v),
      ),
    );
  }

  Widget _buildDetailPanel() {
    return Scrollbar(
      controller: _detailScrollController,
      child: ListView(
        controller: _detailScrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        children: switch (_selected) {
          _SettingCategory.api => _buildApiSettings(),
          _SettingCategory.display => _buildDisplaySettings(),
          _SettingCategory.general => _buildGeneralSettings(),
          _SettingCategory.panel => _buildPanelSettings(),
          _SettingCategory.log => _buildLogSettings(),
        },
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  List<Widget> _buildApiSettings() {
    return [
      _buildCard(
        children: [
          _buildPlatformDropdown(),
          _buildThinDivider(),
          _buildApiKeyField(),
          _buildThinDivider(),
          _buildModelField(),
          _buildThinDivider(),
          _buildEnableBalanceToggle(),
          if (_enableBalance) ...[_buildThinDivider(), _buildBalanceUrlField()],
          _buildThinDivider(),
          _buildChatUrlField(),
        ],
      ),
    ];
  }

  List<Widget> _buildPanelSettings() {
    return [
      _buildWeixinCard(),
      _buildDashboardPanelCard(),
      _buildWeatherApiCard(),
      _buildPhotoWallSettingsCard(),
      _buildCarouselSettingsCard(),
      _buildDailyQuoteCard(),
      _buildBalanceSettingsCard(),
      _buildScheduleCard(),
      _buildNewsCard(),
      _buildNotesCard(),
      _buildTranslateCard(),
      _buildScriptCard(),
    ];
  }

  Widget _buildDailyQuoteCard() {
    return _buildCard(
      children: [
        _buildSectionTitle(
          '每日一言',
          svgIcon: 'assets/svg/setting-panel-ic/每日一言.svg',
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: '类型',
          child: _buildSegmented<String>(
            value: _dailyQuoteType,
            items: _dailyQuoteTypes.keys.toList(),
            labelBuilder: (v) => _dailyQuoteTypes[v] ?? v,
            onChanged: (v) async {
              setState(() => _dailyQuoteType = v);
              final settings = await SettingsService.load();
              settings.dailyQuoteType = v;
              await SettingsService.save(settings);
            },
          ),
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: '国家',
          child: _buildSegmented<String>(
            value: _dailyQuoteCountry,
            items: _dailyQuoteCountries.keys.toList(),
            labelBuilder: (v) => _dailyQuoteCountries[v] ?? v,
            onChanged: (v) async {
              setState(() => _dailyQuoteCountry = v);
              final settings = await SettingsService.load();
              settings.dailyQuoteCountry = v;
              await SettingsService.save(settings);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceSettingsCard() {
    return _buildCard(
      children: [
        _buildSectionTitle(
          '模型余额',
          svgIcon: 'assets/svg/setting-panel-ic/余额.svg',
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: '更新频率',
          child: _buildSegmented<int>(
            value: _balanceRefreshInterval,
            items: _balanceRefreshIntervals.keys.toList(),
            labelBuilder: (v) => _balanceRefreshIntervals[v] ?? '$v秒',
            onChanged: (v) async {
              setState(() => _balanceRefreshInterval = v);
              final settings = await SettingsService.load();
              settings.balanceRefreshInterval = v;
              await SettingsService.save(settings);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoWallSettingsCard() {
    return _buildCard(
      children: [
        _buildSectionTitle(
          '照片墙',
          svgIcon: 'assets/svg/setting-panel-ic/045_照片.svg',
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: '切换频率',
          child: _buildSegmented<int>(
            value: _photoWallSwitchInterval,
            items: _photoWallSwitchIntervals.keys.toList(),
            labelBuilder: (v) => _photoWallSwitchIntervals[v] ?? '$v秒',
            onChanged: (v) async {
              setState(() => _photoWallSwitchInterval = v);
              final settings = await SettingsService.load();
              settings.photoWallSwitchInterval = v;
              await SettingsService.save(settings);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCarouselSettingsCard() {
    return _buildCard(
      children: [
        _buildSectionTitle(
          '轮播图',
          svgIcon: 'assets/svg/setting-panel-ic/轮播.svg',
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: '切换速度',
          child: _buildSegmented<int>(
            value: _carouselSwitchInterval,
            items: _carouselSwitchIntervals.keys.toList(),
            labelBuilder: (v) => _carouselSwitchIntervals[v] ?? '$v秒',
            onChanged: (v) async {
              setState(() => _carouselSwitchInterval = v);
              final settings = await SettingsService.load();
              settings.carouselSwitchInterval = v;
              await SettingsService.save(settings);
              HomeScreen.triggerSettingsChange();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEnableBalanceToggle() {
    return _DropdownRow(
      label: '余额查询',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _enableBalance ? '已开启' : '已关闭',
            style: const TextStyle(color: Color(0xFF555555), fontSize: 14),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _enableBalance,
              activeThumbColor: const Color(0xFF66BB6A),
              activeTrackColor: Colors.black12,
              inactiveThumbColor: Colors.grey,
              inactiveTrackColor: Colors.black12,
              onChanged: (v) => setState(() => _enableBalance = v),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDisplaySettings() {
    return [
      _buildUserInfoCard(),
      _buildCard(
        children: [
          _DropdownRow(
            label: '全局主题',
            child: _buildSegmented<String>(
              value: _appTheme,
              items: const ['light', 'dark'],
              labelBuilder: (v) => v == 'light' ? '浅色' : '深色',
              onChanged: (v) => setState(() => _appTheme = v),
            ),
          ),
          _buildThinDivider(),
          _DropdownRow(
            label: '助手形象',
            child: _buildSegmented<String>(
              value: _petStyle,
              items: const ['colorful', 'round'],
              labelBuilder: (v) => v == 'colorful' ? '炫彩' : '雅黑',
              onChanged: (v) => setState(() => _petStyle = v),
            ),
          ),
          _buildThinDivider(),
          _buildMenuBgSelector(),
        ],
      ),
      _buildCard(
        children: [
          _buildSectionTitle('快捷键'),
          _buildThinDivider(),
          _buildHotkeyRow('打开助手', 'Ctrl+`'),
          _buildThinDivider(),
          _buildHotkeyRow('打开Agent', 'Alt+`'),
          _buildThinDivider(),
          _buildHotkeyRow('打开设置', 'Alt+Ctrl+`'),
        ],
      ),
    ];
  }

  Widget _buildSectionTitle(String title, {String? svgIcon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (svgIcon != null) ...[
            SvgPicture.asset(svgIcon, width: 22, height: 22),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotkeyRow(String label, String hotkey) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF555555), fontSize: 14),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              hotkey,
              style: const TextStyle(color: Color(0xFF333333), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinDivider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Colors.black.withValues(alpha: 0.08),
    );
  }

  List<Widget> _buildGeneralSettings() {
    return [
      _buildCard(
        children: [
          _buildAutoStartToggle(),
        ],
      ),
      _buildCard(children: [_buildClaudeHookInstaller()]),
    ];
  }

  /// 日志分类的显示名称
  static const _logCategoryNames = <String, String>{
    'system': '系统日志',
    'weixin': 'Clawbot日志',
    'llm': 'LLM 日志',
  };

  List<Widget> _buildLogSettings() {
    final categories = ['system', 'weixin', 'llm'];
    final widgets = <Widget>[
      _buildSectionTitle('日志开关'),
    ];
    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      if (i > 0) {
        widgets.add(_buildThinDivider());
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            _logCategoryNames[cat] ?? cat,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
      widgets.add(
        _buildLogToggleRow(
          label: '控制台输出',
          value: _logCategories[cat]?.console ?? true,
          onChanged: (v) {
            setState(() {
              final cur = _logCategories[cat] ?? const LogCategoryConfig();
              _logCategories[cat] = cur.copyWith(console: v);
            });
          },
        ),
      );
      widgets.add(
        _buildLogToggleRow(
          label: '日志文件',
          value: _logCategories[cat]?.file ?? true,
          onChanged: (v) {
            setState(() {
              final cur = _logCategories[cat] ?? const LogCategoryConfig();
              _logCategories[cat] = cur.copyWith(file: v);
            });
          },
        ),
      );
    }
    return [_buildCard(children: widgets)];
  }

  Widget _buildLogToggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF555555), fontSize: 14),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeColor: const Color(0xFF66BB6A),
              activeTrackColor: Colors.black12,
              inactiveThumbColor: Colors.grey,
              inactiveTrackColor: Colors.black12,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeyField() {
    return _DropdownRow(
      label: 'API Key',
      child: TextField(
        controller: _apiKeyController,
        obscureText: _obscureApiKey,
        style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
        decoration: InputDecoration(
          hintText: 'sk-...',
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.03),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureApiKey ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: Colors.black38,
            ),
            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
          ),
        ),
      ),
    );
  }

  Widget _buildModelField() {
    return _DropdownRow(
      label: '模型',
      child: TextField(
        controller: _modelController,
        style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
        decoration: InputDecoration(
          hintText: PlatformConfig.defaultChatModel(_platform),
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.03),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformDropdown() {
    final items = PlatformConfig.platforms.keys.toList();
    return _DropdownRow(
      label: 'AI平台',
      child: _buildDropdown<String>(
        value: _platform,
        items: items,
        itemBuilder: (k) {
          return DropdownMenuItem(
            value: k,
            child: Text(PlatformConfig.platforms[k]?.name ?? k),
          );
        },
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            // 保存当前平台的配置
            _apiConfigs[_platform] = PlatformApiConfig(
              apiKey: _apiKeyController.text.trim(),
              balanceUrl: _balanceUrlController.text.trim(),
              chatUrl: _chatUrlController.text.trim(),
              model: _modelController.text.trim(),
              enableBalance: _enableBalance,
            );
            // 切换到新平台
            _platform = v;
            // 加载新平台的配置（若无则用默认值）
            final cfg = _apiConfigs[v];
            _apiKeyController.text = cfg?.apiKey ?? '';
            _balanceUrlController.text = (cfg?.balanceUrl.isNotEmpty == true)
                ? cfg!.balanceUrl
                : PlatformConfig.defaultBalanceUrl(v);
            _chatUrlController.text = (cfg?.chatUrl.isNotEmpty == true)
                ? cfg!.chatUrl
                : PlatformConfig.defaultChatUrl(v);
            _modelController.text = (cfg?.model.isNotEmpty == true)
                ? cfg!.model
                : PlatformConfig.defaultChatModel(v);
            _enableBalance = cfg?.enableBalance ?? true;
          });
        },
      ),
    );
  }

  Widget _buildBalanceUrlField() {
    return _DropdownRow(
      label: '余额接口',
      child: TextField(
        controller: _balanceUrlController,
        style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
        decoration: InputDecoration(
          hintText: 'https://api.deepseek.com/user/balance',
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.03),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildChatUrlField() {
    return _DropdownRow(
      label: 'Chat API',
      child: TextField(
        controller: _chatUrlController,
        style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
        decoration: InputDecoration(
          hintText: 'https://api.deepseek.com/v1/chat/completions',
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.03),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherApiCard() {
    return _buildCard(
      children: [
        _buildSectionTitle(
          '天气服务 (和风天气)',
          svgIcon: 'assets/svg/setting-panel-ic/045_天气.svg',
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: 'API ID',
          child: TextField(
            controller: _weatherApiIdController,
            style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
            decoration: InputDecoration(
              hintText: '输入 Project ID',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: 'API Key',
          child: TextField(
            controller: _weatherApiKeyController,
            obscureText: _obscureWeatherApiKey,
            style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
            decoration: InputDecoration(
              hintText: '输入 HMAC-SHA256 密钥',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureWeatherApiKey
                      ? Icons.visibility_off
                      : Icons.visibility,
                  size: 18,
                  color: Colors.black38,
                ),
                onPressed: () => setState(
                  () => _obscureWeatherApiKey = !_obscureWeatherApiKey,
                ),
              ),
            ),
          ),
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: 'API Host',
          child: TextField(
            controller: _weatherApiHostController,
            style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
            decoration: InputDecoration(
              hintText: 'devapi.qweather.com',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: '城市',
          child: TextField(
            controller: _weatherCityController,
            style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
            decoration: InputDecoration(
              hintText: '上海',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        _buildThinDivider(),
      ],
    );
  }

  Widget _buildDashboardPanelCard() {
    return _buildCard(
      children: [
        _buildSectionTitle(
          '控制面板',
          svgIcon: 'assets/svg/setting-panel-ic/控制面板.svg',
        ),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildScheduleCard() {
    return _buildCard(
      children: [
        _buildSectionTitle(
          '日程',
          svgIcon: 'assets/svg/setting-panel-ic/_ 日程.svg',
        ),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildNewsCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('新闻', svgIcon: 'assets/svg/setting-panel-ic/新闻.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildFavoritesCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('收藏', svgIcon: 'assets/svg/setting-panel-ic/收藏.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildNotesCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('笔记', svgIcon: 'assets/svg/setting-panel-ic/笔记.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildTranslateCard() {
    final allLangs = TranslateLang.values;
    // 确保 _translateEnabledLangs 有默认值
    if (_translateEnabledLangs.isEmpty) {
      _translateEnabledLangs = allLangs.map((e) => e.name).toList();
    }
    return _buildCard(
      children: [
        _buildSectionTitle('翻译', svgIcon: 'assets/svg/setting-panel-ic/翻译.svg'),
        _buildThinDivider(),
        // 是否显示翻译选项
        _buildLogToggleRow(
          label: '显示翻译选项',
          value: _showTranslateLangSelector,
          onChanged: (v) {
            setState(() => _showTranslateLangSelector = v);
          },
        ),
        _buildThinDivider(),
        // 可选语言
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '可选语言',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ),
        ...allLangs.map((lang) {
          final enabled = _translateEnabledLangs.contains(lang.name);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (enabled) {
                  _translateEnabledLangs.remove(lang.name);
                } else {
                  _translateEnabledLangs.add(lang.name);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    enabled
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: enabled
                        ? const Color(0xFF66BB6A)
                        : const Color(0xFFBBBBBB),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    lang.label,
                    style: const TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildScriptCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('脚本', svgIcon: 'assets/svg/setting-panel-ic/脚本.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildWeixinCard() {
    final connected = _weixinConnected;
    final connecting = _weixinConnecting || _weixinConnectLoading;
    final hasAccount = _weixinBotId.isNotEmpty;

    // 状态文字与颜色
    String statusText;
    Color statusColor;
    if (_weixinState == WeixinConnectionState.reconnecting) {
      statusText = '正在重连…';
      statusColor = Colors.blue;
    } else if (connecting) {
      statusText = '连接中…';
      statusColor = Colors.blue;
    } else if (connected) {
      statusText = '已连接';
      statusColor = const Color(0xFF66BB6A);
    } else if (_weixinState == WeixinConnectionState.error) {
      statusText = '连接异常';
      statusColor = Colors.redAccent;
    } else if (_weixinEnabled && hasAccount) {
      statusText = '已启用 · 等待连接';
      statusColor = Colors.blue;
    } else if (hasAccount) {
      statusText = '已绑定 · 未连接';
      statusColor = Colors.orange;
    } else {
      statusText = '未绑定';
      statusColor = const Color(0xFF999999);
    }

    return _buildCard(
      children: [
        _buildSectionTitle('claw bot'),
        _buildThinDivider(),

        // 状态显示
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (connecting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (hasAccount) ...[
                const Spacer(),
                Text(
                  'Bot: ${_weixinBotId.length > 12 ? '${_weixinBotId.substring(0, 12)}...' : _weixinBotId}',
                  style: const TextStyle(
                    color: Color(0xFFBBBBBB),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),

        if (_weixinError?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _weixinError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
          ),

        _buildThinDivider(),

        // 操作按钮行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (!hasAccount)
                _buildWeixinActionButton(
                  label: '扫码绑定',
                  icon: Icons.qr_code_scanner,
                  color: const Color(0xFF66BB6A),
                  onTap: connecting ? null : _startWeixinQrLogin,
                  loading: _weixinQrLoading,
                )
              else ...[
                if (connecting)
                  _buildWeixinActionButton(
                    label: '取消连接',
                    icon: Icons.link_off,
                    color: Colors.orange,
                    onTap: _disconnectWeixin,
                    loading: _weixinConnectLoading,
                  )
                else if (!connected)
                  _buildWeixinActionButton(
                    label: _weixinEnabled ? '重试' : '连接',
                    icon: Icons.link,
                    color: const Color(0xFF66BB6A),
                    onTap: _connectWeixin,
                    loading: _weixinConnectLoading,
                  )
                else
                  _buildWeixinActionButton(
                    label: '断开',
                    icon: Icons.link_off,
                    color: Colors.orange,
                    onTap: _disconnectWeixin,
                    loading: _weixinConnectLoading,
                  ),
                const SizedBox(width: 8),
                _buildWeixinActionButton(
                  label: '解绑',
                  icon: Icons.delete_outline,
                  color: const Color(0xFFE57373),
                  onTap: _weixinConnectLoading ? null : _unbindWeixin,
                  loading: false,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeixinActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required bool loading,
  }) {
    return Expanded(
      child: SizedBox(
        height: 36,
        child: ElevatedButton.icon(
          onPressed: loading ? null : onTap,
          icon: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                )
              : Icon(icon, size: 16),
          label: Text(
            loading ? '等待扫码...' : label,
            style: const TextStyle(fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startWeixinQrLogin() async {
    setState(() => _weixinQrLoading = true);
    final loginClient = WeixinILinkClient(token: '');
    try {
      final account = await showWeixinQrLoginDialog(
        context: context,
        client: loginClient,
      );

      if (!mounted) return;

      if (account != null) {
        final status = await HomeScreen.bindWeixinAccount(account);
        if (!mounted) return;
        _applyWeixinStatus(status);
        setState(() => _weixinQrLoading = false);
        AppToast.show(context, message: '微信绑定成功');
      } else {
        setState(() => _weixinQrLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _weixinQrLoading = false);
        AppToast.show(context, message: '绑定失败：$e');
      }
    } finally {
      loginClient.dispose();
    }
  }

  Future<void> _connectWeixin() async {
    setState(() => _weixinConnectLoading = true);
    try {
      final status = await HomeScreen.setWeixinEnabled(true);
      if (mounted) {
        _applyWeixinStatus(status);
        AppToast.show(context, message: '微信服务已启用');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _weixinConnectLoading = false);
        AppToast.show(context, message: '连接失败：$e');
        LogService.error('微信连接失败: $e', category: 'weixin');
      }
    }
  }

  Future<void> _disconnectWeixin() async {
    setState(() => _weixinConnectLoading = true);
    try {
      final status = await HomeScreen.setWeixinEnabled(false);
      if (mounted) {
        _applyWeixinStatus(status);
        AppToast.show(context, message: '微信服务已关闭');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _weixinConnectLoading = false);
        AppToast.show(context, message: '断开失败：$e');
      }
    }
  }

  Future<void> _unbindWeixin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑微信'),
        content: const Text('确定要解绑微信吗？解绑后 AI 自动回复将停止。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('解绑'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final status = await HomeScreen.logoutWeixin();
        if (!mounted) return;
        _applyWeixinStatus(status);
        AppToast.show(context, message: '微信已解绑');
      } catch (e) {
        if (mounted) {
          AppToast.show(context, message: '解绑失败：$e');
        }
      }
    }
  }

  Widget _buildPlaceholder() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        '暂无设置项',
        style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('用户信息'),
        _buildThinDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.black.withValues(alpha: 0.06),
                      backgroundImage:
                          _userAvatarPath.isNotEmpty &&
                              File(_userAvatarPath).existsSync()
                          ? FileImage(File(_userAvatarPath))
                          : null,
                      child:
                          _userAvatarPath.isEmpty ||
                              !File(_userAvatarPath).existsSync()
                          ? const Icon(
                              Icons.person,
                              size: 32,
                              color: Color(0xFFBBBBBB),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 14,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '头像',
                      style: TextStyle(color: Color(0xFF999999), fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点击更换头像',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.4),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (_userAvatarPath.isNotEmpty || _userName.isNotEmpty)
                TextButton(
                  onPressed: _clearUserInfo,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF999999),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: const Text('清除', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        _buildThinDivider(),
        _DropdownRow(
          label: '用户名',
          child: TextField(
            controller: _userNameController,
            style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
            decoration: InputDecoration(
              hintText: '未设置',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.25)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.first.path;
    if (sourcePath == null) return;
    final destPath = await SettingsService.avatarFilePath();
    await File(sourcePath).copy(destPath);
    if (!mounted) return;
    setState(() => _userAvatarPath = destPath);
  }

  void _clearUserInfo() {
    setState(() {
      _userName = '';
      _userAvatarPath = '';
      _userNameController.clear();
    });
  }

  Widget _buildMenuBgSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '菜单背景',
                style: TextStyle(color: Color(0xFF555555), fontSize: 14),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _pickMenuBgImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.upload_rounded,
                        size: 16,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '上传图片',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 用户上传的图片
          if (_menuBgFilePath.isNotEmpty &&
              File(_menuBgFilePath).existsSync()) ...[
            GestureDetector(
              onTap: () => setState(() {
                _menuBgImage = _menuBgFilePath;
              }),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _menuBgImage == _menuBgFilePath
                        ? const Color(0xFF66BB6A)
                        : Colors.black.withValues(alpha: 0.1),
                    width: _menuBgImage == _menuBgFilePath ? 2.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(_menuBgFilePath), fit: BoxFit.cover),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: GestureDetector(
                        onTap: _clearMenuBgFile,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 内置图片列表
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _menuBgOptions.map((path) {
              final isSelected = path == _menuBgImage;
              final isNone = path.isEmpty;
              return GestureDetector(
                onTap: () => setState(() {
                  _menuBgImage = path;
                }),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF66BB6A)
                          : Colors.black.withValues(alpha: 0.1),
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: isNone
                      ? Container(
                          color: const Color(0xFFE0E0E0),
                          child: const Center(
                            child: Text(
                              '无',
                              style: TextStyle(
                                color: Color(0xFF999999),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : Image.asset(path, fit: BoxFit.cover),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMenuBgImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.first.path;
    if (sourcePath == null) return;
    final ext = sourcePath.split('.').last.toLowerCase();
    final destPath = await SettingsService.menuBgFilePath(ext);
    await File(sourcePath).copy(destPath);
    if (!mounted) return;
    setState(() {
      _menuBgFilePath = destPath;
      _menuBgImage = destPath;
    });
  }

  void _clearMenuBgFile() {
    setState(() {
      _menuBgFilePath = '';
      _menuBgImage = _menuBgOptions[1]; // 默认选第一个内置图
    });
  }

  Widget _buildAutoStartToggle() {
    return _DropdownRow(
      label: '开机自启',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Transform.scale(
          scale: 0.8,
          child: Switch(
            value: _autoStart,
            activeColor: const Color(0xFF66BB6A),
            activeTrackColor: Colors.black12,
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.black12,
            onChanged: (v) => setState(() => _autoStart = v),
          ),
        ),
      ),
    );
  }

  Widget _buildClaudeHookInstaller() {
    final statusText = _claudeHookInstalled ? '已安装全局 Hook' : '未安装';
    final statusColor = _claudeHookInstalled
        ? Colors.green.shade700
        : const Color(0xFF999999);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Claude Hook',
                style: TextStyle(color: Color(0xFF555555), fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                '更新 Claude Code 后需要重新安装',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                _claudeHookInstalled
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                color: statusColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 14),
                ),
              ),
              TextButton.icon(
                onPressed: _installingClaudeHooks ? null : _installClaudeHooks,
                icon: _installingClaudeHooks
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black26,
                        ),
                      )
                    : const Icon(Icons.download_done_rounded, size: 16),
                label: Text(_claudeHookInstalled ? '重新安装' : '安装'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _installClaudeHooks() async {
    setState(() => _installingClaudeHooks = true);
    try {
      final result = await ClaudeHookInstaller.installGlobalHooks();
      if (!mounted) return;
      setState(() {
        _claudeHookInstalled = true;
        _installingClaudeHooks = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('全局 Hook 已安装：${result.settingsPath}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _installingClaudeHooks = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('安装失败：$error'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // iOS 风格分段选择器，不弹窗，点击即切换
  Widget _buildSegmented<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: items.map((item) {
          final selected = item == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(item),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  labelBuilder(item),
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF333333)
                        : const Color(0xFF999999),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    DropdownMenuItem<T> Function(T)? itemBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black38),
          items: itemBuilder != null
              ? items.map(itemBuilder).toList()
              : items.map((e) {
                  return DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString()),
                  );
                }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 100,
            height: 40,
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(
                  0xFF66BB6A,
                ).withValues(alpha: 0.85),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('保存', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    // 保存当前平台的配置到 map
    _apiConfigs[_platform] = PlatformApiConfig(
      apiKey: _apiKeyController.text.trim(),
      balanceUrl: _balanceUrlController.text.trim(),
      chatUrl: _chatUrlController.text.trim(),
      model: _modelController.text.trim(),
      enableBalance: _enableBalance,
    );

    // 基于已有设置更新，保留面板布局等设置界面不管理的字段
    final existing = await SettingsService.load();
    existing.platform = _platform;
    existing.apiConfigs = _apiConfigs;
    existing.autoStart = _autoStart;
    existing.logCategories = Map.of(_logCategories);
    existing.language = _language;
    existing.appTheme = _appTheme;
    existing.petStyle = _petStyle;
    existing.userName = _userNameController.text.trim();
    existing.userAvatarPath = _userAvatarPath;
    existing.menuBgImage = _menuBgImage;
    existing.menuBgFilePath = _menuBgFilePath;
    existing.weatherApiId = _weatherApiIdController.text.trim();
    existing.weatherApiKey = _weatherApiKeyController.text.trim();
    existing.weatherApiHost = _weatherApiHostController.text.trim();
    existing.weatherCity = _weatherCityController.text.trim();
    existing.showTranslateLangSelector = _showTranslateLangSelector;
    existing.translateEnabledLangs = List.of(_translateEnabledLangs);
    await SettingsService.save(existing);

    // 通知设置变更
    HomeScreen.triggerSettingsChange();
    AgentService.syncLogSettings();
    LogService.updateConfig(Map.of(_logCategories));

    // 通知悬浮球窗口刷新（助手形象等）
    HomeScreen.menuChannel.invokeMethod('settings_saved');

    if (!mounted) return;
    AppToast.show(context, message: '设置已保存');
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF555555), fontSize: 14),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
