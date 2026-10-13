part of 'home_screen.dart';

/// '/' 命令：命令注册表 + prepareInput 命令分派。
/// 新增命令 = 在 [_HomeScreenCommands._buildCommands] 里加一条 ChatCommand；
/// execute 内操作页面状态需自行 mounted 保护。
/// /setting 的设置弹窗（系统设置 + Agent 设置）见 settings_dialog.dart。
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
        name: 'setting',
        description: '打开设置（API / 翻译 / 日志 / Agent / 界面）',
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
}
