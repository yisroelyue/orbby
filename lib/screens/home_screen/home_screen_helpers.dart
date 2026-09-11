part of 'home_screen.dart';

/// HomeScreen 的纯展示辅助逻辑集中在这里，避免页面状态类继续膨胀。
extension _HomeScreenFormatting on _HomeScreenState {
  String _toolDisplayName(String name) {
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
      'str_replace_editor': '编辑器操作',
      'terminal_open': '打开终端',
      'terminal_send': '发送终端输入',
      'terminal_read': '读取终端输出',
      'terminal_close': '关闭终端',
      'terminal_list': '终端列表',
      'skill': '加载技能',
    };
    return aliases[name] ?? '工具操作';
  }

  String _formatToolDetails(String name, dynamic parameters, dynamic result, {String? error}) {
    // ask_user_question 的参数/结果由工具行下方的问答留痕卡承载，不再重复 dump
    if (name == 'ask_user_question') {
      return error != null && error.isNotEmpty ? '错误: $error' : '';
    }
    final lines = <String>[];
    if (parameters is Map) {
      // 工具卡片展示调用摘要；执行结果由对话正文/文件变更预览承载。
      final command = parameters['command'];
      if (command != null) lines.add(command.toString());
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
        if ((entry.key == 'content' || entry.key == 'oldString' || entry.key == 'newString') && entry.value is String && (entry.value as String).length > 160) {
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
