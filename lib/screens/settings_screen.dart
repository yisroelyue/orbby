import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../config/platform.dart';
import '../config/settings.dart';
import '../services/claude_hook_installer.dart';
import '../widgets/interactive_icon.dart';

enum _SettingCategory { api, display, general }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const settingsChannel = WindowMethodChannel(
    'orbby_settings_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _detailScrollController = ScrollController();
  _SettingCategory _selected = _SettingCategory.display;

  late final TextEditingController _apiKeyController;
  late final TextEditingController _balanceUrlController;
  late final TextEditingController _chatUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _userNameController;
  String _platform = 'deepseek';
  Map<String, PlatformApiConfig> _apiConfigs = {};
  bool _enableBalance = true;
  bool _obscureApiKey = true;
  bool _autoStart = false;
  String _language = 'zh';
  bool _showPhotoWallPanel = true;
  bool _showAgentChatPanel = true;
  String _appTheme = 'light';
  String _petStyle = 'colorful';
  double _menuAutoHideDelay = 3.0;
  bool _showBalancePanel = true;
  bool _showTranslatePanel = true;
  bool _showTodoPanel = true;
  bool _showFavoritesPanel = true;
  bool _showAppSquarePanel = true;
  bool _showVibePanel = true;
  bool _claudeHookInstalled = false;
  bool _installingClaudeHooks = false;
  bool _loading = true;
  String _userName = '';
  String _userAvatarPath = '';
  String _menuBgImage = '';

  /// 内置菜单背景图列表
  static const _menuBgOptions = <String>[
    '',
    'assets/png/menuBg/1.jpg',
    'assets/png/menuBg/2.jpg',
    'assets/png/menuBg/3.jpg',
    'assets/png/menuBg/4.jpg',
    'assets/png/menuBg/5.jpg',
  ];

  static const _languages = {'zh': '中文', 'en': 'English'};

  static const _categoryItems = <(_SettingCategory, IconData, String)>[
    (_SettingCategory.display, Icons.palette_outlined, '显示设置'),
    (_SettingCategory.general, Icons.tune_rounded, '通用设置'),
    (_SettingCategory.api, Icons.api_rounded, 'API 配置'),
  ];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _balanceUrlController = TextEditingController();
    _chatUrlController = TextEditingController();
    _modelController = TextEditingController();
    _userNameController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsService.load();
    final claudeHookInstalled = await ClaudeHookInstaller.isGlobalHookInstalled();
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
      _language = s.language;
      _showPhotoWallPanel = s.showPhotoWallPanel;
      _showAgentChatPanel = s.showAgentChatPanel;
      _appTheme = s.appTheme;
      _showBalancePanel = s.showBalancePanel;
      _showTranslatePanel = s.showTranslatePanel;
      _showTodoPanel = s.showTodoPanel;
      _showFavoritesPanel = s.showFavoritesPanel;
      _showAppSquarePanel = s.showAppSquarePanel;
      _showVibePanel = s.showVibePanel;
      _petStyle = s.petStyle;
      _menuAutoHideDelay = s.menuAutoHideDelay;
      _userName = s.userName;
      _userAvatarPath = s.userAvatarPath;
      _menuBgImage = s.menuBgImage;
      _userNameController.text = s.userName;
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
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      child: MaterialApp(
        scaffoldMessengerKey: _messengerKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSansSC'),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            color: const Color(0xFFF0F0F0),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.black26,
                      strokeWidth: 2,
                    ),
                  )
                : Column(
                    children: [
                      _buildTitleBar(),
                      const SizedBox(height: 8),
                      Expanded(child: _buildBody()),
                      _buildBottomBar(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
        child: Row(
          children: [
            const Icon(Icons.settings, color: Colors.black54, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '系统设置',
                style: TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InteractiveIcon(
              onTap: () => windowManager.hide(),
              child: const Icon(Icons.close, color: Colors.black38, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      children: [
        _buildSidebar(),
        _buildDivider(),
        Expanded(child: _buildDetailPanel()),
      ],
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: 200,
      child: ListView(
        primary: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: _categoryItems.map((item) {
          final (cat, icon, label) = item;
          final isActive = _selected == cat;
          return _SidebarItem(
            icon: icon,
            label: label,
            active: isActive,
            onTap: () => setState(() => _selected = cat),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.black.withValues(alpha: 0.08),
    );
  }

  Widget _buildDetailPanel() {
    return Container(
      color: const Color(0xFFE8E8E8),
      child: Scrollbar(
        controller: _detailScrollController,
        child: ListView(
          controller: _detailScrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          children: switch (_selected) {
            _SettingCategory.api     => _buildApiSettings(),
            _SettingCategory.display => _buildDisplaySettings(),
            _SettingCategory.general => _buildGeneralSettings(),
          },
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
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
          if (_enableBalance) ...[
            _buildThinDivider(),
            _buildBalanceUrlField(),
          ],
          _buildThinDivider(),
          _buildChatUrlField(),
        ],
      ),
    ];
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
          _buildThinDivider(),
          _DropdownRow(
            label: '顶部工作区-自动收起间隔',
            labelWidth: 200,
            child: _buildSegmented<double>(
              value: _menuAutoHideDelay,
              items: const [0.5, 3, 5, 10],
              labelBuilder: (v) => v == v.roundToDouble() ? '${v.toInt()}秒' : '$v秒',
              onChanged: (v) => setState(() => _menuAutoHideDelay = v),
            ),
          ),
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
      _buildCard(
        children: [
          _buildPanelToggle('照片墙', _showPhotoWallPanel, (v) => setState(() => _showPhotoWallPanel = v)),
          _buildThinDivider(),
          _buildPanelToggle('Agent 对话', _showAgentChatPanel, (v) => setState(() => _showAgentChatPanel = v)),
          _buildThinDivider(),
          _buildPanelToggle('AI流量管理', _showBalancePanel, (v) => setState(() => _showBalancePanel = v)),
          _buildThinDivider(),
          _buildPanelToggle('Vibe任务监控', _showVibePanel, (v) => setState(() => _showVibePanel = v), compact: true),
          _buildThinDivider(),
          _buildPanelToggle('翻译', _showTranslatePanel, (v) => setState(() => _showTranslatePanel = v)),
          _buildThinDivider(),
          _buildPanelToggle('我的笔记', _showTodoPanel, (v) => setState(() => _showTodoPanel = v)),
          _buildThinDivider(),
          _buildPanelToggle('我的收藏', _showFavoritesPanel, (v) => setState(() => _showFavoritesPanel = v)),
          _buildThinDivider(),
          _buildPanelToggle('应用中心', _showAppSquarePanel, (v) => setState(() => _showAppSquarePanel = v)),
        ],
      ),
    ];
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF333333),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildHotkeyRow(String label, String hotkey) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF555555), fontSize: 14)),
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


  Widget _buildPanelToggle(String label, bool value, ValueChanged<bool> onChanged, {bool compact = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: const Color(0xFF555555), fontSize: compact ? 12 : 14)),
          Transform.scale(
            scale: compact ? 0.68 : 0.8,
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

  List<Widget> _buildGeneralSettings() {
    return [
      _buildCard(
        children: [
          _buildLanguageDropdown(),
          _buildThinDivider(),
          _buildAutoStartToggle(),
        ],
      ),
      _buildCard(
        children: [
          _buildClaudeHookInstaller(),
        ],
      ),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
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
                      backgroundImage: _userAvatarPath.isNotEmpty && File(_userAvatarPath).existsSync()
                          ? FileImage(File(_userAvatarPath))
                          : null,
                      child: _userAvatarPath.isEmpty || !File(_userAvatarPath).existsSync()
                          ? const Icon(Icons.person, size: 32, color: Color(0xFFBBBBBB))
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
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 3)],
                        ),
                        child: const Icon(Icons.camera_alt, size: 14, color: Color(0xFF666666)),
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
                    const Text('头像', style: TextStyle(color: Color(0xFF999999), fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      '点击更换头像',
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (_userAvatarPath.isNotEmpty || _userName.isNotEmpty)
                TextButton(
                  onPressed: _clearUserInfo,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF999999),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          const Text('菜单背景', style: TextStyle(color: Color(0xFF555555), fontSize: 14)),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _menuBgOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final path = _menuBgOptions[index];
                final isSelected = path == _menuBgImage;
                final isNone = path.isEmpty;
                return GestureDetector(
                  onTap: () => setState(() => _menuBgImage = path),
                  child: Container(
                    width: 56,
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
                              child: Text('无', style: TextStyle(color: Color(0xFF999999), fontSize: 13)),
                            ),
                          )
                        : Image.asset(path, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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

  Widget _buildClaudeHookInstaller() {
    final statusText = _claudeHookInstalled ? '已安装全局 Hook' : '未安装';
    final statusColor =
        _claudeHookInstalled ? Colors.green.shade700 : const Color(0xFF999999);

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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('全局 Hook 已安装：${result.settingsPath}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _installingClaudeHooks = false);
      _messengerKey.currentState?.showSnackBar(
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
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  labelBuilder(item),
                  style: TextStyle(
                    color: selected ? const Color(0xFF333333) : const Color(0xFF999999),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 100,
            height: 40,
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF66BB6A).withValues(alpha: 0.85),
                foregroundColor: Colors.black87,
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

  void _saveSettings() {
    // 保存当前平台的配置到 map
    _apiConfigs[_platform] = PlatformApiConfig(
      apiKey: _apiKeyController.text.trim(),
      balanceUrl: _balanceUrlController.text.trim(),
      chatUrl: _chatUrlController.text.trim(),
      model: _modelController.text.trim(),
      enableBalance: _enableBalance,
    );

    final settings = AppSettings(
      platform: _platform,
      apiConfigs: _apiConfigs,
      autoStart: _autoStart,
      language: _language,
      showPhotoWallPanel: _showPhotoWallPanel,
      showAgentChatPanel: _showAgentChatPanel,
      appTheme: _appTheme,
      showBalancePanel: _showBalancePanel,
      showTranslatePanel: _showTranslatePanel,
      showTodoPanel: _showTodoPanel,
      showFavoritesPanel: _showFavoritesPanel,
      showAppSquarePanel: _showAppSquarePanel,
      showVibePanel: _showVibePanel,
      petStyle: _petStyle,
      menuAutoHideDelay: _menuAutoHideDelay,
      userName: _userNameController.text.trim(),
      userAvatarPath: _userAvatarPath,
      menuBgImage: _menuBgImage,
    );
    SettingsService.save(settings);
    SettingsScreen.settingsChannel.invokeMethod('settings_saved');
    windowManager.hide();
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? Colors.black.withValues(alpha: 0.08)
        : _hovering
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: const Color(0xFF333333),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: const Color(0xFF333333),
                    fontSize: 13,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({required this.label, required this.child, this.labelWidth = 80});

  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
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