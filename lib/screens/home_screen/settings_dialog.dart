part of 'home_screen.dart';

/// /setting 设置弹窗：原独立 settings 窗口的系统设置（API / 翻译 / 日志）
/// 迁移合并进本弹窗，外加 Agent 设置（系统提示词 / 使用规范）与界面开关
/// （深色主题 / 会话标签）。API 设置为自由配置列表（任意多份 ApiProfile，
/// 内置平台降级为模板填充；配置的新增/编辑/删除只在本弹窗，聊天输入框的
/// 模型浮层只做激活配置 + 模型的快速切换）。
///
/// 保存语义：除「显示会话标签」切换即生效外，其余项（API / 翻译 / 日志 /
/// 提示词 / 使用规范 / 深色主题）统一点底部「保存」落盘并广播
/// settingsChanged，同时刷新顶栏模型标签；深色主题随保存切换并刷新弹窗落盘
///
/// 弹窗挂在 navigator 层（ChatThemeScope 之外），主题 token 直接取
/// State 的 _themeData，不走 ChatTheme.of(dialogContext)。hub 的
/// open_settings（托盘菜单 / Ctrl+Alt+` 快捷键）经 menuSettingsRequested
/// 信号转达（见 menu_window_signals.dart），与本命令共用 [_showAgentSettings]。
extension _HomeScreenSettingsDialog on _HomeScreenState {
  Future<void> _showAgentSettings() async {
    // 快捷键 / 托盘可在弹窗已开时再次触发，守卫防叠出多层
    if (_settingsDialogOpen) return;
    _settingsDialogOpen = true;
    final settings = await SettingsService.load();
    if (!mounted) {
      _settingsDialogOpen = false;
      return;
    }
    // 弹窗内可切深色主题：theme 用 var 持有，切换后取新值重建
    var theme = _themeData;
    var dialogThemeDark = _themeDark;

    // ── 弹窗编辑态（闭包持有；「保存」时写回 settings 落盘）─────────────────
    // API 配置：profiles 是副本（条目字段可变；切配置/保存前先 stashForm 把
    // 表单暂存回条目），editingId = 正在编辑的条目，activeId = 激活项
    // （「设为当前使用」改，保存时随 profiles 一起生效）
    var profiles = [for (final p in settings.profiles) p.copy()];
    var editingId = settings.activeProfileId;
    var activeId = settings.activeProfileId;
    // load 兜底保证 profiles 至少一条；防御性再校验 editingId
    if (!profiles.any((p) => p.id == editingId)) editingId = profiles.first.id;
    ApiProfile? profileById(String id) {
      for (final p in profiles) {
        if (p.id == id) return p;
      }
      return null;
    }

    String profileLabel(ApiProfile p) =>
        p.name.trim().isEmpty ? '未命名配置' : p.name.trim();

    final initial = profileById(editingId)!;
    final profileName = TextEditingController(text: initial.name);
    var protocol = initial.protocol;
    final apiKey = TextEditingController(text: initial.apiKey);
    final chatUrl = TextEditingController(text: initial.baseUrl);
    final model = TextEditingController(text: initial.model);
    // 模板填充下拉是"动作型"控件：选中即填充、随即复位回占位项，不持久
    var templateKey = '';

    /// 当前表单暂存进编辑中的条目（切配置 / 新增 / 删除 / 保存前调用）
    void stashForm() {
      final editing = profileById(editingId);
      if (editing == null) return;
      editing
        ..name = profileName.text.trim()
        ..protocol = protocol
        ..baseUrl = chatUrl.text.trim()
        ..apiKey = apiKey.text.trim()
        ..model = model.text.trim();
    }

    /// 条目载入表单（切配置 / 新增 / 模板填充后同步输入框与协议下拉）
    void loadForm(ApiProfile p) {
      profileName.text = p.name;
      protocol = p.protocol;
      apiKey.text = p.apiKey;
      chatUrl.text = p.baseUrl;
      model.text = p.model;
    }
    final tencentSecretId = TextEditingController(
      text: settings.tencentSecretId,
    );
    final tencentSecretKey = TextEditingController(
      text: settings.tencentSecretKey,
    );
    final tencentRegion = TextEditingController(text: settings.tencentRegion);
    final tencentProjectId = TextEditingController(
      text: '${settings.tencentProjectId}',
    );
    var translationProvider = settings.translationProvider;
    var logCategories = Map.of(settings.logCategories);
    var llmLogRequest = settings.llmLogRequest;
    var llmLogResponse = settings.llmLogResponse;
    var obscureApiKey = true;
    var obscureSecretKey = true;

    final prompt = TextEditingController(text: settings.agentSystemPrompt);
    final rules = TextEditingController(text: settings.agentUsageRules);

    Future<void> saveAll() async {
      // 统一写回全部编辑态（提示词 / 使用规范不再自动保存，随按钮落盘）
      stashForm();
      settings
        ..profiles = profiles
        ..activeProfileId = activeId
        ..logCategories = Map.of(logCategories)
        ..llmLogRequest = llmLogRequest
        ..llmLogResponse = llmLogResponse
        ..translationProvider = translationProvider
        ..tencentSecretId = tencentSecretId.text.trim()
        ..tencentSecretKey = tencentSecretKey.text.trim()
        ..tencentRegion = tencentRegion.text.trim().isEmpty
              ? 'ap-guangzhou'
              : tencentRegion.text.trim()
        ..tencentProjectId = int.tryParse(tencentProjectId.text.trim()) ?? 0
        ..agentSystemPrompt = prompt.text
        ..agentUsageRules = rules.text;
      await SettingsService.save(settings);
      // 广播设置变更：本 engine（日志 / Agent 配置）在 main.dart 的监听里同步，
      // 其余窗口经 hub 转发各自处理
      AppEvents.emit(AppEvents.settingsChanged);
      if (!mounted) return;
      setState(() {
        _modelLabel = _modelLabelText(settings.activeProfile);
      });
      AppToast.show(context, message: '设置已保存');
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          StatefulBuilder(
            builder: (_, setDialogState) => Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.of(dialogContext).pop();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Dialog(
                backgroundColor: Colors.transparent,
                // 收窄默认边距：弹窗宽度才能跟上窗口宽（否则被 Dialog 约束 clamp）
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.raised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.line),
                    boxShadow: theme.popShadows,
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  width: 720,
                  height: MediaQuery.sizeOf(dialogContext).height * 0.78,
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            '设置',
                            style: TextStyle(
                              color: theme.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFamily: _fontFamily,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: Icon(Icons.close, size: 18, color: theme.ink3),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── 界面 ──────────────────────────────────
                              _settingsCard(
                                theme,
                                title: '界面',
                                children: [
                                  _settingsSwitchRow(
                                    theme,
                                    '深色主题',
                                    icon: theme.isDark
                                        ? Icons.dark_mode_outlined
                                        : Icons.light_mode_outlined,
                                    value: dialogThemeDark,
                                    // 只改弹窗编辑态，不立即切主题——
                                    // 「保存」时经 _toggleTheme 生效
                                    onChanged: (value) => setDialogState(
                                      () => dialogThemeDark = value,
                                    ),
                                  ),
                                  _settingsSwitchRow(
                                    theme,
                                    '显示会话标签',
                                    icon: Icons.tab_outlined,
                                    value: settings.showSessionTabs,
                                    onChanged: (value) async {
                                      setDialogState(
                                        () => settings.showSessionTabs = value,
                                      );
                                      if (mounted) {
                                        setState(
                                          () => _showSessionTabs = value,
                                        );
                                      }
                                      await SettingsService.save(settings);
                                    },
                                  ),
                                ],
                              ),
                              // ── Agent 设置 ────────────────────────────
                              _settingsCard(theme, title: 'Agent 设置', children: [
                                const SizedBox(height: 2),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '自定义系统提示词',
                                    style: TextStyle(
                                      color: theme.ink2,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                _settingsAreaField(theme, prompt),
                                const SizedBox(height: 14),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '自定义使用规范',
                                    style: TextStyle(
                                      color: theme.ink2,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                _settingsAreaField(theme, rules),
                                const SizedBox(height: 4),
                              ]),
                              // ── API 设置 ──────────────────────────────
                              // 自由配置列表：配置下拉（激活项带 ●）+ 新增/删除/
                              // 设为当前使用；下方表单编辑当前条目。模板填充 =
                              // 选内置平台一键覆盖名称/协议/端点/模型（不动 Key）
                              _settingsCard(theme, title: 'API 设置', children: [
                                _settingsRow(
                                  theme,
                                  '配置',
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _settingsDropdown<String>(
                                          theme: theme,
                                          value: editingId,
                                          items: [
                                            for (final p in profiles) p.id,
                                          ],
                                          itemBuilder: (id) => DropdownMenuItem(
                                            value: id,
                                            child: Text(
                                              profileById(id)!.id == activeId
                                                  ? '● ${profileLabel(profileById(id)!)}'
                                                  : profileLabel(
                                                      profileById(id)!,
                                                    ),
                                            ),
                                          ),
                                          // 切配置 = 暂存当前表单再载入目标条目
                                          onChanged: (v) {
                                            if (v == null || v == editingId) {
                                              return;
                                            }
                                            setDialogState(() {
                                              stashForm();
                                              editingId = v;
                                              loadForm(profileById(v)!);
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _settingsActionButton(theme, '新增', () {
                                        setDialogState(() {
                                          stashForm();
                                          final created = ApiProfile(
                                            name: '新配置',
                                          );
                                          profiles.add(created);
                                          editingId = created.id;
                                          loadForm(created);
                                        });
                                      }),
                                      const SizedBox(width: 6),
                                      _settingsActionButton(
                                        theme,
                                        '删除',
                                        danger: true,
                                        () {
                                          setDialogState(() {
                                            stashForm();
                                            profiles.removeWhere(
                                              (p) => p.id == editingId,
                                            );
                                            // 副本删空则补默认模板（保持
                                            // 「profiles 至少一条」不变式）
                                            if (profiles.isEmpty) {
                                              profiles.add(
                                                ApiProfile(
                                                  name:
                                                      PlatformConfig
                                                          .platforms['deepseek']!
                                                          .name,
                                                  protocol:
                                                      PlatformConfig
                                                          .templateProtocol(
                                                        'deepseek',
                                                      ),
                                                  baseUrl:
                                                      PlatformConfig
                                                          .defaultChatUrl(
                                                        'deepseek',
                                                      ),
                                                  model:
                                                      PlatformConfig
                                                          .defaultChatModel(
                                                        'deepseek',
                                                      ),
                                                ),
                                              );
                                            }
                                            // 删的是激活项则激活切首条，
                                            // 编辑焦点随之落到激活项
                                            if (!profiles.any(
                                              (p) => p.id == activeId,
                                            )) {
                                              activeId = profiles.first.id;
                                            }
                                            editingId = activeId;
                                            loadForm(profileById(editingId)!);
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      _settingsActionButton(
                                        theme,
                                        '设为当前使用',
                                        editingId == activeId
                                            ? null
                                            : () => setDialogState(
                                              () => activeId = editingId,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                _settingsRow(
                                  theme,
                                  '名称',
                                  _settingsField(theme, profileName, '如：DeepSeek 官方'),
                                ),
                                _settingsRow(
                                  theme,
                                  '协议',
                                  _settingsDropdown<String>(
                                    theme: theme,
                                    value: protocol,
                                    items: ApiProtocol.all,
                                    itemBuilder: (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(ApiProtocol.displayName(v)),
                                    ),
                                    onChanged: (v) => setDialogState(
                                      () => protocol = v ?? ApiProtocol.openai,
                                    ),
                                  ),
                                ),
                                _settingsRow(
                                  theme,
                                  '模板填充',
                                  _settingsDropdown<String>(
                                    theme: theme,
                                    value: templateKey,
                                    items: [
                                      '',
                                      ...PlatformConfig.platforms.keys,
                                    ],
                                    itemBuilder: (k) => DropdownMenuItem(
                                      value: k,
                                      child: Text(
                                        k.isEmpty
                                            ? '选择内置平台一键填充（可选）'
                                            : PlatformConfig.platforms[k]?.name ??
                                                  k,
                                      ),
                                    ),
                                    // 动作型下拉：选中即覆盖四字段并复位回占位项
                                    onChanged: (v) {
                                      if (v == null || v.isEmpty) return;
                                      setDialogState(() {
                                        templateKey = '';
                                        final target = profileById(editingId)!;
                                        target
                                          ..name =
                                              PlatformConfig
                                                  .platforms[v]
                                                  ?.name ??
                                              v
                                          ..protocol =
                                              PlatformConfig.templateProtocol(v)
                                          ..baseUrl =
                                              PlatformConfig.defaultChatUrl(v)
                                          ..model =
                                              PlatformConfig.defaultChatModel(v);
                                        loadForm(target);
                                      });
                                    },
                                  ),
                                ),
                                _settingsRow(
                                  theme,
                                  'API Key',
                                  _settingsField(
                                    theme,
                                    apiKey,
                                    'sk-...',
                                    obscure: obscureApiKey,
                                    suffix: IconButton(
                                      icon: Icon(
                                        obscureApiKey
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        size: 18,
                                        color: theme.ink3,
                                      ),
                                      onPressed: () => setDialogState(
                                        () => obscureApiKey = !obscureApiKey,
                                      ),
                                    ),
                                  ),
                                ),
                                _settingsRow(
                                  theme,
                                  '模型',
                                  _settingsField(
                                    theme,
                                    model,
                                    'deepseek-chat',
                                  ),
                                ),
                                _settingsRow(
                                  theme,
                                  'Chat API',
                                  _settingsField(
                                    theme,
                                    chatUrl,
                                    'https://api.deepseek.com/v1/chat/completions',
                                  ),
                                ),
                              ]),
                              // ── 翻译设置 ──────────────────────────────
                              _settingsCard(theme, title: '翻译设置', children: [
                                _settingsRow(
                                  theme,
                                  '翻译服务',
                                  _settingsDropdown<String>(
                                    theme: theme,
                                    value: translationProvider,
                                    items: const ['llm', 'tencent'],
                                    itemBuilder: (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                        v == 'tencent' ? '腾讯云翻译' : 'LLM 翻译',
                                      ),
                                    ),
                                    onChanged: (v) => setDialogState(
                                      () => translationProvider = v ?? 'llm',
                                    ),
                                  ),
                                ),
                                if (translationProvider == 'tencent') ...[
                                  _settingsRow(
                                    theme,
                                    'SecretId',
                                    _settingsField(
                                      theme,
                                      tencentSecretId,
                                      '腾讯云 SecretId',
                                    ),
                                  ),
                                  _settingsRow(
                                    theme,
                                    'SecretKey',
                                    _settingsField(
                                      theme,
                                      tencentSecretKey,
                                      '腾讯云 SecretKey',
                                      obscure: obscureSecretKey,
                                      suffix: IconButton(
                                        icon: Icon(
                                          obscureSecretKey
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          size: 18,
                                          color: theme.ink3,
                                        ),
                                        onPressed: () => setDialogState(
                                          () =>
                                              obscureSecretKey =
                                                  !obscureSecretKey,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _settingsRow(
                                    theme,
                                    '地域',
                                    _settingsField(
                                      theme,
                                      tencentRegion,
                                      'ap-guangzhou',
                                    ),
                                  ),
                                  _settingsRow(
                                    theme,
                                    '项目 ID',
                                    _settingsField(
                                      theme,
                                      tencentProjectId,
                                      '0',
                                    ),
                                  ),
                                ],
                              ]),
                              // ── 日志设置 ──────────────────────────────
                              _settingsCard(theme, title: '日志设置', children: [
                                _settingsSubLabel(theme, '系统日志'),
                                _settingsSwitchRow(
                                  theme,
                                  '控制台输出',
                                  value:
                                      logCategories['system']?.console ?? true,
                                  onChanged: (v) => setDialogState(() {
                                    final cur =
                                        logCategories['system'] ??
                                        const LogCategoryConfig();
                                    logCategories['system'] = cur.copyWith(
                                      console: v,
                                    );
                                  }),
                                ),
                                _settingsSwitchRow(
                                  theme,
                                  '日志文件',
                                  value: logCategories['system']?.file ?? true,
                                  onChanged: (v) => setDialogState(() {
                                    final cur =
                                        logCategories['system'] ??
                                        const LogCategoryConfig();
                                    logCategories['system'] = cur.copyWith(
                                      file: v,
                                    );
                                  }),
                                ),
                                _settingsSubLabel(theme, 'LLM 日志'),
                                _settingsSwitchRow(
                                  theme,
                                  '请求日志',
                                  value: llmLogRequest,
                                  onChanged: (v) =>
                                      setDialogState(() => llmLogRequest = v),
                                ),
                                _settingsSwitchRow(
                                  theme,
                                  '回复日志',
                                  value: llmLogResponse,
                                  onChanged: (v) =>
                                      setDialogState(() => llmLogResponse = v),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                      _settingsDivider(theme),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton(
                              // 主题随保存生效：改过才切（_toggleTheme 自带
                              // setState + 落盘），并取新 token 刷新弹窗
                              onPressed: () async {
                                await saveAll();
                                if (dialogThemeDark != _themeDark) {
                                  await _toggleTheme();
                                  theme = _themeData;
                                  setDialogState(() {});
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.accent,
                                // 琥珀底墨字（同发送钮的墨色例外，见主题规范）
                                foregroundColor: const Color(0xFF202020),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                '保存',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
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

    prompt.dispose();
    rules.dispose();
    profileName.dispose();
    apiKey.dispose();
    chatUrl.dispose();
    model.dispose();
    tencentSecretId.dispose();
    tencentSecretKey.dispose();
    tencentRegion.dispose();
    tencentProjectId.dispose();
    _settingsDialogOpen = false;
  }

  // ── 弹窗内的通用小件（token 全部来自传入的 theme，不写死色值）────────────

  /// 分区卡片：sunken 沉底 + lineSoft 描边 + 圆角，头部为分区标题。
  /// 弹窗底是 raised，卡片沉一层、卡内输入框/下拉再浮回 raised，形成层级。
  Widget _settingsCard(
    ChatThemeData theme, {
    required String title,
    required List<Widget> children,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
    decoration: BoxDecoration(
      color: theme.sunken,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: theme.lineSoft),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 0, 6),
          child: Text(
            title,
            style: TextStyle(
              color: theme.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    ),
  );

  Widget _settingsDivider(ChatThemeData theme) => Divider(
    height: 1,
    thickness: 0.5,
    color: theme.lineSoft,
  );

  Widget _settingsSubLabel(ChatThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 0, 2),
    child: Text(text, style: TextStyle(color: theme.ink3, fontSize: 12)),
  );

  /// 左标签 + 右控件的单行表单（下拉 / 输入框）
  Widget _settingsRow(ChatThemeData theme, String label, Widget child) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: TextStyle(color: theme.ink2, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      );

  /// 左标签 + 右开关的单行（标签与开关之间自动撑开）
  Widget _settingsSwitchRow(
    ChatThemeData theme,
    String label, {
    IconData? icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: theme.ink3),
          const SizedBox(width: 8),
        ],
        Text(label, style: TextStyle(color: theme.ink2, fontSize: 13)),
        const Spacer(),
        Transform.scale(
          scale: 0.7,
          child: Switch(
            value: value,
            // 中性开关（刻意不用琥珀）：轨道走前景色（浅色黑 / 深色亮白），
            // 滑块取反色保证对比；深色下纯黑轨道不可见，故走 ink 而非写死
            activeTrackColor: theme.ink,
            activeColor: theme.isDark
                ? const Color(0xFF202020)
                : Colors.white,
            inactiveThumbColor: theme.ink2,
            inactiveTrackColor: theme.line,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );

  /// 单行输入框（raised 底浮起于分区卡 + lineSoft 描边 + accent 聚焦）
  Widget _settingsField(
    ChatThemeData theme,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    Widget? suffix,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    cursorColor: theme.accentDeep,
    style: TextStyle(
      color: theme.ink,
      fontSize: 13,
      height: 1.4,
      fontFamily: _fontFamily,
    ),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: theme.ink3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.lineSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.lineSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.accent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: theme.raised,
      suffixIcon: suffix,
    ),
  );

  /// 多行输入区（提示词 / 使用规范），值随「保存」统一落盘
  Widget _settingsAreaField(
    ChatThemeData theme,
    TextEditingController controller,
  ) => TextField(
    controller: controller,
    minLines: 1,
    maxLines: 12,
    cursorColor: theme.accentDeep,
    style: TextStyle(
      color: theme.body,
      fontSize: 14,
      height: 1.45,
      fontFamily: _fontFamily,
    ),
    decoration: InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.lineSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.lineSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.accent),
      ),
      contentPadding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      filled: true,
      fillColor: theme.raised,
    ),
  );

  /// 卡片内的小动作按钮（新增 / 删除 / 设为当前使用）：中性描边（lineSoft +
  /// ink2 字），danger 走语义红；仅"设为当前使用"等状态性入口可能传 null 置灰
  Widget _settingsActionButton(
    ChatThemeData theme,
    String label,
    VoidCallback? onPressed, {
    bool danger = false,
  }) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: danger ? theme.danger : theme.ink2,
      side: BorderSide(color: danger ? theme.danger : theme.lineSoft),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(label, style: const TextStyle(fontSize: 12.5)),
  );

  /// 下拉框（raised 底浮起于分区卡，展开层同用 raised 底，条目文字走 ink）
  Widget _settingsDropdown<T>({
    required ChatThemeData theme,
    required T value,
    required List<T> items,
    required DropdownMenuItem<T> Function(T) itemBuilder,
    required ValueChanged<T?> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: theme.raised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        dropdownColor: theme.raised,
        borderRadius: BorderRadius.circular(8),
        style: TextStyle(
          color: theme.ink,
          fontSize: 13,
          fontFamily: _fontFamily,
        ),
        icon: Icon(Icons.arrow_drop_down, size: 20, color: theme.ink3),
        items: items.map(itemBuilder).toList(),
        onChanged: onChanged,
      ),
    ),
  );
}
