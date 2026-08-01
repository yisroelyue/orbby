import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../config/platform.dart';
import '../../config/settings.dart';
import '../../services/agent_service.dart';
import '../../services/claude_hook_installer.dart';
import '../../screens/home_screen.dart';
import '../../widgets/app_toast.dart';

enum _SettingCategory { display, general, api, panel }

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _detailScrollController = ScrollController();
  _SettingCategory _selected = _SettingCategory.display;

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
  bool _llmLogEnabled = false;
  String _language = 'zh';
  String _appTheme = 'light';
  String _petStyle = 'colorful';
  bool _claudeHookInstalled = false;
  bool _installingClaudeHooks = false;
  bool _loading = true;
  String _userName = '';
  String _userAvatarPath = '';
  String _menuBgImage = '';
  String _menuBgFilePath = '';
  String _dailyQuoteType = '';
  String _dailyQuoteCountry = '';
  int _balanceRefreshInterval = 0;
  int _photoWallSwitchInterval = 30;
  int _carouselSwitchInterval = 12;

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

  static const _languages = {'zh': '中文', 'en': 'English'};

  static const _categoryItems = <(_SettingCategory, IconData, String)>[
    (_SettingCategory.display, Icons.palette_outlined, '显示设置'),
    (_SettingCategory.general, Icons.tune_rounded, '通用设置'),
    (_SettingCategory.api, Icons.smart_toy_outlined, '模型设置'),
    (_SettingCategory.panel, Icons.dashboard_outlined, '面板设置'),
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
      _llmLogEnabled = s.llmLogEnabled;
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
      _claudeHookInstalled = claudeHookInstalled;
      _loading = false;
    });
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
    super.dispose();
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
      _buildDashboardPanelCard(),
      _buildWeatherApiCard(),
      _buildPhotoWallSettingsCard(),
      _buildCarouselSettingsCard(),
      _buildDailyQuoteCard(),
      _buildBalanceSettingsCard(),
      _buildScheduleCard(),
      _buildNewsCard(),
      _buildFavoritesCard(),
      _buildNotesCard(),
      _buildTranslateCard(),
      _buildScriptCard(),
    ];
  }

  Widget _buildDailyQuoteCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('每日一言',
            svgIcon: 'assets/svg/setting-panel-ic/每日一言.svg'),
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
        _buildSectionTitle('模型余额',
            svgIcon: 'assets/svg/setting-panel-ic/余额.svg'),
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
        _buildSectionTitle('照片墙',
            svgIcon: 'assets/svg/setting-panel-ic/045_照片.svg'),
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
        _buildSectionTitle('轮播图',
            svgIcon: 'assets/svg/setting-panel-ic/轮播.svg'),
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
          _buildLanguageDropdown(),
          _buildThinDivider(),
          _buildAutoStartToggle(),
          _buildThinDivider(),
          _buildLlmLogToggle(),
        ],
      ),
      _buildCard(children: [_buildClaudeHookInstaller()]),
    ];
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
        _buildSectionTitle('天气服务 (和风天气)',
            svgIcon: 'assets/svg/setting-panel-ic/045_天气.svg'),
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
                  _obscureWeatherApiKey ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: Colors.black38,
                ),
                onPressed: () => setState(() => _obscureWeatherApiKey = !_obscureWeatherApiKey),
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
        _buildSectionTitle('控制面板',
            svgIcon: 'assets/svg/setting-panel-ic/控制面板.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildScheduleCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('日程',
            svgIcon: 'assets/svg/setting-panel-ic/_ 日程.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildNewsCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('新闻',
            svgIcon: 'assets/svg/setting-panel-ic/新闻.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildFavoritesCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('收藏',
            svgIcon: 'assets/svg/setting-panel-ic/收藏.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildNotesCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('笔记',
            svgIcon: 'assets/svg/setting-panel-ic/笔记.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildTranslateCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('翻译',
            svgIcon: 'assets/svg/setting-panel-ic/翻译.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
  }

  Widget _buildScriptCard() {
    return _buildCard(
      children: [
        _buildSectionTitle('脚本',
            svgIcon: 'assets/svg/setting-panel-ic/脚本.svg'),
        _buildThinDivider(),
        _buildPlaceholder(),
      ],
    );
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upload_rounded, size: 16, color: Colors.black.withValues(alpha: 0.5)),
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
          if (_menuBgFilePath.isNotEmpty && File(_menuBgFilePath).existsSync()) ...[
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
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
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

  Widget _buildLanguageDropdown() {
    return _DropdownRow(
      label: '语言',
      child: _buildSegmented<String>(
        value: _language,
        items: _languages.keys.toList(),
        labelBuilder: (k) => _languages[k]!,
        onChanged: (v) => setState(() => _language = v),
      ),
    );
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

  Widget _buildLlmLogToggle() {
    return _DropdownRow(
      label: 'LLM 日志',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Transform.scale(
          scale: 0.8,
          child: Switch(
            value: _llmLogEnabled,
            activeColor: const Color(0xFF66BB6A),
            activeTrackColor: Colors.black12,
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.black12,
            onChanged: (v) => setState(() => _llmLogEnabled = v),
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
    existing.llmLogEnabled = _llmLogEnabled;
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
    await SettingsService.save(existing);

    // 通知设置变更
    HomeScreen.triggerSettingsChange();
    AgentService.syncLogSettings();

    // 通知悬浮球窗口刷新（助手形象等）
    HomeScreen.menuChannel.invokeMethod('settings_saved');

    if (!mounted) return;
    AppToast.show(context, message: '设置已保存');
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.child,
  });

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
