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

  /// 匹配输入文本中的 prepareInput 命令前缀（如 `/image-analyze 找出问题`）。
  /// 只匹配"命令名+空格+说明"形态——纯命令名交给精确匹配走准备态
  /// （与命令面板确认行为一致）；非 prepareInput 前缀返回 null。
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
        description: '开启新对话，可通过 /session 命令找回历史会话',
        execute: _startNewConversation,
      ),
      ChatCommand(
        name: 'clear',
        description: '清空当前上下文，但继续使用当前会话',
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
        name: 'image-analyze',
        description: '分析粘贴的图片（确认后 Ctrl+V 粘贴图片，再回车）',
        // prepareInput 行为由宿主（_confirmCommand/_sendMessage）按 behavior 分派，
        // execute 不承载动作
        behavior: ChatCommandBehavior.prepareInput,
        execute: () {},
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
    ];
  }

  /// /setting：Agent 设置弹窗（自定义系统提示词与使用规范）
  Future<void> _showAgentSettings() async {
    final settings = await SettingsService.load();
    if (!mounted) return;
    final prompt = TextEditingController(text: settings.agentSystemPrompt);
    final rules = TextEditingController(text: settings.agentUsageRules);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.all(20),
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Expanded(child: Text('Agent 设置', style: TextStyle(color: Color(0xFFEAEAEA), fontSize: 14, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close, size: 18, color: Colors.white54)),
              ]),
              const SizedBox(height: 18),
              TextField(controller: prompt, maxLines: 6, style: const TextStyle(color: Colors.white70), decoration: const InputDecoration(labelText: '自定义系统提示词', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), filled: true, fillColor: Color(0xFF292929))),
              const SizedBox(height: 14),
              TextField(controller: rules, maxLines: 6, style: const TextStyle(color: Colors.white70), decoration: const InputDecoration(labelText: '自定义使用规范', labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), filled: true, fillColor: Color(0xFF292929))),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: Colors.white54))),
                const SizedBox(width: 8),
                FilledButton(onPressed: () async { settings.agentSystemPrompt = prompt.text; settings.agentUsageRules = rules.text; await SettingsService.save(settings); if (dialogContext.mounted) Navigator.pop(dialogContext); }, child: const Text('保存')),
              ]),
            ]),
        ),
      ),
    );
    prompt.dispose();
    rules.dispose();
  }
}
