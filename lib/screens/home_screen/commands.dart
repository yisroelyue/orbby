part of 'home_screen.dart';

/// '/' 命令：命令注册表 + Agent 设置弹窗。
/// 新增命令 = 在 [_HomeScreenCommands._buildCommands] 里加一条 ChatCommand；
/// execute 内操作页面状态需自行 mounted 保护。
extension _HomeScreenCommands on _HomeScreenState {
  /// prepareInput 类命令确认后：把 `/命令名 ` 写入输入框等待补充内容
  /// （不调 AgentService）；后续发送经 [_matchPrepareCommand] 剥离前缀
  void _prepareInputCommand(ChatCommand cmd) {
    if (!mounted) return;
    final text = '/${cmd.name} ';
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputFocus.requestFocus();
  }

  /// 匹配输入文本中的 prepareInput 命令前缀。
  /// 只匹配"命令名+空格+说明"形态；纯命令名经精确匹配以空参数执行
  /// （面板确认仍走准备态，写回 `/命令名 ` 等待补参）；非 prepareInput 前缀返回 null。
  (ChatCommand, String)? _matchPrepareCommand(String text) {
    for (final cmd in _palette.commands) {
      if (cmd.behavior != ChatCommandBehavior.prepareInput) continue;
      final prefix = '/${cmd.name} ';
      if (text.toLowerCase().startsWith(prefix.toLowerCase())) {
        return (cmd, text.substring(prefix.length).trim());
      }
    }
    return null;
  }

  /// 命令注册表：新增命令在这里加一条 ChatCommand 即可
  List<ChatCommand> _buildCommands() {
    return [
      ChatCommand(
        name: 'help',
        description: '查看所有命令',
        execute: () {
          final buf = StringBuffer('可用命令：');
          for (final c in _palette.commands) {
            buf.write('\n- `/${c.name}` — ${c.description}');
          }
          _addLocalMessage(buf.toString());
        },
      ),
      ChatCommand(
        name: 'session',
        description: '查看并切换历史会话',
        execute: _showSessionPicker,
      ),
      ChatCommand(
        name: 'new',
        description: '另开一个新的会话标签页（旧会话保留在 tab 栏可切回）',
        execute: _startNewConversation,
      ),
      ChatCommand(
        name: 'close',
        description: '关闭当前会话标签页',
        execute: _closeCurrentSessionTab,
      ),
      ChatCommand(
        name: 'clear',
        description: '清空当前上下文和当前会话历史',
        execute: _clearCurrentConversation,
      ),
      ChatCommand(
        name: 'clear-session',
        description: '清理所有历史会话，并开启新的会话',
        execute: _clearAllSessions,
      ),
      ChatCommand(
        name: 'compact',
        description: '压缩对话上下文',
        execute: _runCompact,
      ),
      ChatCommand(
        name: 'status',
        description: '查看当前上下文长度和会话状态',
        execute: _showAgentStatus,
      ),
      ChatCommand(
        name: 'cd',
        description: '切换工作区目录：/cd 路径，不带参数查看当前',
        behavior: ChatCommandBehavior.prepareInput,
        execute: () {},
        executeWithArgument: _changeWorkspace,
      ),
      ChatCommand(
        name: 'file',
        description: '浏览当前工作区文件并插入文件路径',
        execute: _showFilePicker,
      ),
      ChatCommand(
        name: 'personality',
        description: '切换性格：humor、serious、concise',
        behavior: ChatCommandBehavior.prepareInput,
        execute: () {},
        executeWithArgument: _setPersonality,
      ),
      ChatCommand(
        name: 'rollback',
        description: '回滚上一次文件改动',
        execute: () => _addLocalMessage(FileUndoService.undoLast()),
      ),
      ChatCommand(
        name: 'retry',
        description: '重新生成最后一条回复',
        execute: _retryLastMessage,
      ),
      ChatCommand(
        name: 'copy',
        description: '复制当前会话的完整 JSON',
        execute: _copyConversationJson,
      ),
      ChatCommand(
        name: 'copy-txt',
        description: '复制当前会话的文本内容',
        execute: _copyConversationText,
      ),
      ChatCommand(
        name: 'apps',
        description: '打开应用中心',
        execute: () => HomeScreen.menuChannel.invokeMethod('open_app_center'),
      ),
      ChatCommand(
        name: 'sys_setting',
        description: '打开设置窗口',
        execute: () => HomeScreen.menuChannel.invokeMethod('open_settings'),
      ),
      ChatCommand(
        name: 'setting',
        description: '打开 Agent 设置',
        execute: _showAgentSettings,
      ),
      ChatCommand(name: 'permission-off', description: '关闭授权，操作前询问', execute: () => _setPermissionMode('ask', '已关闭全局授权，恢复操作前询问。')),
      ChatCommand(name: 'permission-all', description: '全局授权所有读写执行操作', execute: () => _setPermissionMode('all', '已开启全局授权，后续操作不再询问。')),
      ChatCommand(name: 'permission-read', description: '只读授权，读取操作不再询问', execute: () => _setPermissionMode('read', '已开启只读授权，读取操作不再询问。')),
      ChatCommand(name: 'permission', description: '查看当前授权模式和已保存权限', execute: _showPermissionStatus),
      ChatCommand(
        name: 'reload-skill',
        description: '重新扫描技能目录（加/改技能文件后生效，无需重启）',
        execute: _reloadSkillsCommand,
      ),
    ];
  }

  /// /setting：Agent 设置弹窗（自定义系统提示词与使用规范）。
  /// 弹窗挂在 navigator 层（ChatThemeScope 之外），主题 token 直接取
  /// State 的 _themeData，不走 ChatTheme.of(dialogContext)
  Future<void> _showAgentSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    final theme = _themeData;
    var dialogThemeDark = _themeDark;
    final prompt = TextEditingController(text: settings.agentSystemPrompt);
    final rules = TextEditingController(text: settings.agentUsageRules);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Focus(
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
          child: Container(
          decoration: BoxDecoration(
            color: theme.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.line),
            boxShadow: theme.popShadows,
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          width: 620,
          height: MediaQuery.sizeOf(dialogContext).height * 0.7,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: Text('Agent 设置', style: TextStyle(color: theme.ink, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: _fontFamily))),
                IconButton(onPressed: () => Navigator.pop(dialogContext), icon: Icon(Icons.close, size: 18, color: theme.ink3)),
              ]),
              const SizedBox(height: 14),
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
              TextField(
                controller: prompt,
                onChanged: (_) => _scheduleAgentSettingsSave(
                  settings,
                  prompt.text,
                  rules.text,
                ),
                minLines: 1,
                maxLines: 12,
                cursorColor: theme.accentDeep,
                style: TextStyle(color: theme.body, fontSize: 14, height: 1.45, fontFamily: _fontFamily),
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
                  fillColor: theme.sunken,
                ),
              ),
              const SizedBox(height: 16),
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
              TextField(
                controller: rules,
                onChanged: (_) => _scheduleAgentSettingsSave(
                  settings,
                  prompt.text,
                  rules.text,
                ),
                minLines: 1,
                maxLines: 12,
                cursorColor: theme.accentDeep,
                style: TextStyle(color: theme.body, fontSize: 14, height: 1.45, fontFamily: _fontFamily),
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
                  fillColor: theme.sunken,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    theme.isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    size: 18,
                    color: theme.ink2,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '深色主题',
                      style: TextStyle(color: theme.ink2, fontSize: 13),
                    ),
                  ),
                  StatefulBuilder(
                    builder: (context, setDialogState) => Transform.scale(
                      scale: 0.82,
                      child: Switch(
                        value: dialogThemeDark,
                        onChanged: (value) {
                          setDialogState(() => dialogThemeDark = value);
                          _toggleTheme();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.tab_outlined, size: 18, color: theme.ink2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '显示会话标签',
                      style: TextStyle(color: theme.ink2, fontSize: 13),
                    ),
                  ),
                  StatefulBuilder(
                    builder: (context, setDialogState) => Transform.scale(
                      scale: 0.82,
                      child: Switch(
                        value: settings.showSessionTabs,
                        onChanged: (value) async {
                          setDialogState(() => settings.showSessionTabs = value);
                          if (mounted) setState(() => _showSessionTabs = value);
                          await SettingsService.save(settings);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ]),
          ),
          ),
        ),
      ),
    );
    prompt.dispose();
    rules.dispose();
  }

  void _scheduleAgentSettingsSave(
    AppSettings settings,
    String prompt,
    String rules,
  ) {
    _agentSettingsSaveTimer?.cancel();
    _agentSettingsSaveTimer = Timer(const Duration(milliseconds: 450), () {
      settings.agentSystemPrompt = prompt;
      settings.agentUsageRules = rules;
      SettingsService.save(settings);
    });
  }
}
