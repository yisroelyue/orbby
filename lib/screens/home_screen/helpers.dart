part of 'home_screen.dart';

/// 工具名 → 中文显示名（纯格式化，状态类与工具步骤折叠组共用，故为库级顶层函数）
String toolDisplayName(String name) {
  const aliases = {
    'ask_user_question': '提问用户',
    'powershell': '执行 PowerShell',
    'bash': '执行 Bash',
    'execute_command': '执行命令',
    'read': '读取文件',
    'write': '写入文件',
    'edit': '编辑文件',
    'delete': '删除文件',
    'glob': '查找文件',
    'grep': '搜索内容',
    'str_replace_editor': '编辑器',
    'terminal_open': '打开终端',
    'terminal_send': '发送终端输入',
    'terminal_read': '读取终端输出',
    'terminal_close': '关闭终端',
    'terminal_list': '终端列表',
    'skill': '加载技能',
  };
  return aliases[name] ?? '工具操作';
}

/// 工具名 → 前置图标 asset（方点与标题之间；无映射返回 null，行首保持原样）。
/// 图标为单色三阶灰，渲染时用 ColorFilter 染 ink2 随主题。
String? toolIconAsset(String name) {
  switch (name) {
    // 编辑类 → 铅笔
    case 'edit':
    case 'write':
    case 'str_replace_editor':
      return 'assets/svg/edit.svg';
    // 读取/查找类 → 眼形
    case 'read':
    case 'glob':
    case 'grep':
      return 'assets/svg/read.svg';
    // 删除
    case 'delete':
      return 'assets/svg/deleted.svg';
    // 命令/终端类 → 提示符
    case 'powershell':
    case 'bash':
    case 'execute_command':
    case 'terminal_open':
    case 'terminal_send':
    case 'terminal_read':
    case 'terminal_close':
    case 'terminal_list':
      return 'assets/svg/terminal.svg';
    default:
      return null;
  }
}

/// HomeScreen 的纯展示辅助逻辑集中在这里，避免页面状态类继续膨胀。
extension _HomeScreenFormatting on _HomeScreenState {
  /// 工具行标题：编辑器类带子命令（如「编辑器 · str_replace」）；
  /// view 本质是读文件，只显示「编辑器」不带子命令
  String _toolRowTitle(_ToolEvent tool) {
    final parameters = tool.parameters;
    final command = parameters is Map ? parameters['command'] : null;
    if (tool.name == 'str_replace_editor' && command != null && command.toString().isNotEmpty) {
      if (command.toString() == 'view') return toolDisplayName(tool.name);
      return '${toolDisplayName(tool.name)} · $command';
    }
    return toolDisplayName(tool.name);
  }

  /// 标题与参数同一行：标题（w600 ink2）+「：」+ 参数摘要（ink3、不加粗），
  /// 超宽自动软换行；无参数（如 ask_user_question）只显示标题
  TextSpan _toolTitleSpan(_ToolEvent tool) {
    final details = tool.name == 'ask_user_question' || tool.parameters == null
        ? ''
        : _formatToolDetails(tool.name, tool.parameters, null);
    return TextSpan(
      children: [
        TextSpan(text: _toolRowTitle(tool)),
        if (details.isNotEmpty) ...[
          const TextSpan(text: '：'),
          // 参数压平成单行（content/命令自带的换行转空格），超宽走软换行
          TextSpan(
            text: details.replaceAll('\r', '').replaceAll('\n', ' '),
            style: TextStyle(color: _themeData.ink3, fontWeight: FontWeight.w400),
          ),
        ],
      ],
    );
  }

  String _formatToolDetails(String name, dynamic parameters, dynamic result, {String? error}) {
    // ask_user_question 的参数/结果由工具行下方的问答留痕卡承载，不再重复 dump
    if (name == 'ask_user_question') {
      return error != null && error.isNotEmpty ? '错误: $error' : '';
    }
    final lines = <String>[];
    if (parameters is Map) {
      // 工具卡片展示调用摘要；执行结果由对话正文/文件变更预览承载。
      // command 裸行仅 shell 类工具（编辑器的 command 是子命令词，已并入行标题）
      final command = parameters['command'];
      if (command != null && (name == 'powershell' || name == 'bash' || name == 'execute_command')) {
        lines.add(command.toString());
      }
      if (name == 'edit') {
        final values = <String>[];
        for (final key in ['path', 'oldString', 'newString', 'replaceAll']) {
          if (!parameters.containsKey(key)) continue;
          final value = parameters[key];
          final display = value is String && value.length > 160 ? '${value.length} 字符' : _humanValue(value);
          if (display.isNotEmpty) values.add('$key: $display');
        }
        if (values.isNotEmpty) lines.add(values.join('，'));
      } else {
      for (final entry in parameters.entries) {
        if (entry.key == 'command' || entry.key == 'description') continue;
        if (name == 'read' && entry.key != 'path') continue;
        if ((name == 'powershell' || name == 'execute_command' || name == 'bash') && entry.key != 'workdir' && entry.key != 'timeoutMs') continue;
        if (name == 'edit' && entry.key != 'path' && entry.key != 'oldString' && entry.key != 'newString' && entry.key != 'replaceAll') continue;
        if ((entry.key == 'content' || entry.key == 'oldString' || entry.key == 'newString' || entry.key == 'old_str' || entry.key == 'new_str' || entry.key == 'file_text') && entry.value is String && (entry.value as String).length > 160) {
          lines.add('${entry.key}: ${(entry.value as String).length} 字符');
          continue;
        }
        final value = _humanValue(entry.value);
        if (value.isNotEmpty) lines.add('${entry.key}: $value');
      }
      }
    } else if (parameters != null) {
      lines.add(_humanValue(parameters));
    }
    if (error != null && error.isNotEmpty) {
      lines.add('错误: $error');
    }
    return lines.join('\n');
  }

  List<String> _formatToolResult(String name, dynamic value) {
    dynamic decoded = value;
    if (value is String) {
      try { decoded = jsonDecode(value); } catch (_) {}
    }
    if (decoded is Map) {
      final lines = <String>[];
      if (decoded['exitCode'] != null) lines.add('退出码: ${decoded['exitCode']}');
      if ((decoded['stdout'] ?? '').toString().trim().isNotEmpty) lines.add(decoded['stdout'].toString().trim());
      if ((decoded['stderr'] ?? '').toString().trim().isNotEmpty) lines.add('错误输出: ${decoded['stderr']}');
      if (name == 'open_terminal' || decoded['sessionId'] != null) {
        final session = decoded['sessionId'];
        if (session != null) lines.add('终端: $session');
        if (decoded['cwd'] != null) lines.add('目录: ${decoded['cwd']}');
      }
      if (lines.isNotEmpty) return lines;
      return decoded.entries.map((e) => '${e.key}: ${_humanValue(e.value)}').toList();
    }
    if (decoded is List) return ['${decoded.length} 项', ...decoded.take(5).map(_humanValue)];
    return [_humanValue(decoded)];
  }

  String _humanValue(dynamic value) {
    if (value == null) return '';
    if (value is Map) return value.entries.map((e) => '${e.key}: ${_humanValue(e.value)}').join(', ');
    if (value is List) return value.map(_humanValue).join(', ');
    return value.toString();
  }
}
