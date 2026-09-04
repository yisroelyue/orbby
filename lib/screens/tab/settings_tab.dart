import 'package:flutter/material.dart';
import 'package:orbby/services/log_service.dart';
import '../../config/platform.dart';
import '../../config/settings.dart';
import '../../services/agent_service.dart';
import '../../services/translate_service.dart';
import '../../screens/home_screen.dart';
import '../../widgets/app_toast.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _detailScrollController = ScrollController();

  late final TextEditingController _apiKeyController;
  late final TextEditingController _chatUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _tencentSecretIdController;
  late final TextEditingController _tencentSecretKeyController;
  late final TextEditingController _tencentRegionController;
  late final TextEditingController _tencentProjectIdController;
  String _platform = 'deepseek';
  Map<String, PlatformApiConfig> _apiConfigs = {};
  bool _obscureApiKey = true;
  bool _obscureTencentSecretKey = true;
  String _translationProvider = 'llm';
  Map<String, LogCategoryConfig> _logCategories = {};
  bool _showTranslateLangSelector = true;
  List<String> _translateEnabledLangs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _chatUrlController = TextEditingController();
    _modelController = TextEditingController();
    _tencentSecretIdController = TextEditingController();
    _tencentSecretKeyController = TextEditingController();
    _tencentRegionController = TextEditingController();
    _tencentProjectIdController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _platform = s.platform;
      _apiConfigs = Map.of(s.apiConfigs);
      final cfg = s.currentApi;
      _apiKeyController.text = cfg.apiKey;
      _chatUrlController.text = cfg.chatUrl.isEmpty
          ? PlatformConfig.defaultChatUrl(s.platform)
          : cfg.chatUrl;
      _modelController.text = cfg.model.isEmpty
          ? PlatformConfig.defaultChatModel(s.platform)
          : cfg.model;
      _logCategories = Map.of(s.logCategories);
      _translationProvider = s.translationProvider;
      _tencentSecretIdController.text = s.tencentSecretId;
      _tencentSecretKeyController.text = s.tencentSecretKey;
      _tencentRegionController.text = s.tencentRegion;
      _tencentProjectIdController.text = '${s.tencentProjectId}';
      _showTranslateLangSelector = s.showTranslateLangSelector;
      _translateEnabledLangs = List.of(s.translateEnabledLangs);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _chatUrlController.dispose();
    _modelController.dispose();
    _tencentSecretIdController.dispose();
    _tencentSecretKeyController.dispose();
    _tencentRegionController.dispose();
    _tencentProjectIdController.dispose();
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
          Expanded(child: _buildDetailPanel()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildDetailPanel() {
    return Scrollbar(
      controller: _detailScrollController,
      child: ListView(
        controller: _detailScrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Text(
              '设置',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          ..._buildApiSettings(),
          ..._buildTranslateSettings(),
          ..._buildLogSettings(),
        ],
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
          _buildSectionTitle('API 设置'),
          _buildThinDivider(),
          _buildPlatformDropdown(),
          _buildThinDivider(),
          _buildApiKeyField(),
          _buildThinDivider(),
          _buildModelField(),
          _buildThinDivider(),
          _buildChatUrlField(),
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

  Widget _buildThinDivider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Colors.black.withValues(alpha: 0.08),
    );
  }

  /// 日志分类的显示名称
  static const _logCategoryNames = <String, String>{
    'system': '系统日志',
    'llm': 'LLM 日志',
  };

  List<Widget> _buildLogSettings() {
    final categories = ['system', 'llm'];
    final widgets = <Widget>[
      _buildSectionTitle('日志设置'),
      _buildThinDivider(),
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

  List<Widget> _buildTranslateSettings() => [_buildTranslateCard()];

  Widget _buildSettingTextField(TextEditingController controller, String hint,
      {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure && _obscureTencentSecretKey,
      style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.03),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: obscure
            ? IconButton(
                icon: Icon(_obscureTencentSecretKey ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _obscureTencentSecretKey = !_obscureTencentSecretKey),
              )
            : null,
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
              chatUrl: _chatUrlController.text.trim(),
              model: _modelController.text.trim(),
            );
            // 切换到新平台
            _platform = v;
            // 加载新平台的配置（若无则用默认值）
            final cfg = _apiConfigs[v];
            _apiKeyController.text = cfg?.apiKey ?? '';
            _chatUrlController.text = (cfg?.chatUrl.isNotEmpty == true)
                ? cfg!.chatUrl
                : PlatformConfig.defaultChatUrl(v);
            _modelController.text = (cfg?.model.isNotEmpty == true)
                ? cfg!.model
                : PlatformConfig.defaultChatModel(v);
          });
        },
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

  Widget _buildTranslateCard() {
    final providerSettings = <Widget>[
      _DropdownRow(label: '翻译服务', child: _buildDropdown<String>(
        value: _translationProvider,
        items: const ['llm', 'tencent'],
        itemBuilder: (v) => DropdownMenuItem(value: v, child: Text(v == 'tencent' ? '腾讯云翻译' : 'LLM 翻译')),
        onChanged: (v) => setState(() => _translationProvider = v ?? 'llm'),
      )),
      if (_translationProvider == 'tencent') ...[
        _DropdownRow(label: 'SecretId', child: _buildSettingTextField(_tencentSecretIdController, '腾讯云 SecretId')),
        _DropdownRow(label: 'SecretKey', child: _buildSettingTextField(_tencentSecretKeyController, '腾讯云 SecretKey', obscure: true)),
        _DropdownRow(label: '地域', child: _buildSettingTextField(_tencentRegionController, 'ap-guangzhou')),
        _DropdownRow(label: '项目 ID', child: _buildSettingTextField(_tencentProjectIdController, '0')),
      ],
      _buildThinDivider(),
    ];
    final allLangs = TranslateLang.values;
    // 确保 _translateEnabledLangs 有默认值
    if (_translateEnabledLangs.isEmpty) {
      _translateEnabledLangs = allLangs.map((e) => e.name).toList();
    }
    return _buildCard(
      children: [
        _buildSectionTitle('翻译设置'),
        _buildThinDivider(),
        ...providerSettings,
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
      chatUrl: _chatUrlController.text.trim(),
      model: _modelController.text.trim(),
    );

    // 基于已有设置更新，保留面板布局等设置界面不管理的字段
    final existing = await SettingsService.load();
    existing.platform = _platform;
    existing.apiConfigs = _apiConfigs;
    existing.logCategories = Map.of(_logCategories);
    existing.showTranslateLangSelector = _showTranslateLangSelector;
    existing.translateEnabledLangs = List.of(_translateEnabledLangs);
    existing.translationProvider = _translationProvider;
    existing.tencentSecretId = _tencentSecretIdController.text.trim();
    existing.tencentSecretKey = _tencentSecretKeyController.text.trim();
    existing.tencentRegion = _tencentRegionController.text.trim().isEmpty
        ? 'ap-guangzhou'
        : _tencentRegionController.text.trim();
    existing.tencentProjectId = int.tryParse(_tencentProjectIdController.text.trim()) ?? 0;
    await SettingsService.save(existing);

    // 通知设置变更
    HomeScreen.triggerSettingsChange();
    AgentService.syncLogSettings();
    LogService.updateConfig(Map.of(_logCategories));

    // 通知悬浮球窗口刷新
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
