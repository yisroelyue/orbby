// 工具：执行终端命令
// 从 orbby-agent/src/tools/execute_command.ts 迁移

import 'dart:io';
import '../types.dart';

/// 超时时间（毫秒），防止命令挂死
const int _defaultTimeout = 30000;

final executeCommandTool = ToolDefinition(
  name: 'execute_command',
  description:
      '在终端中执行一条命令并返回输出。适合运行 git、npm、python 等命令行工具。\n'
      '命令有 30 秒超时限制，避免长时间挂起。\n'
      '当前系统: ${Platform.operatingSystem}，默认 shell: ${Platform.isWindows ? "cmd.exe" : "/bin/sh"}',
  parameters: {
    'type': 'object',
    'properties': {
      'command': {
        'type': 'string',
        'description': '要执行的命令，例如 "git status"、"npm test"、"dir C:\\Users"',
      },
      'cwd': {
        'type': 'string',
        'description': '命令执行的工作目录。不填则使用当前工作目录。',
      },
    },
    'required': ['command'],
  },
  execute: (args) async {
    final command = args['command'] as String?;
    final cwd = args['cwd'] as String?;

    if (command == null || command.isEmpty) {
      return '错误：command 参数无效，需要提供有效的命令字符串';
    }

    final parts = <String>[];

    if (cwd != null && cwd.isNotEmpty) {
      parts.add('工作目录: $cwd');
    }

    try {
      String shell, shellArg;
      if (Platform.isWindows) {
        shell = 'cmd';
        shellArg = '/c';
      } else {
        shell = '/bin/sh';
        shellArg = '-c';
      }

      final process = await Process.start(
        shell,
        [shellArg, command],
        workingDirectory: cwd,
        mode: ProcessStartMode.normal,
      );

      // 设置超时
      final stdoutFuture = process.stdout.transform(const SystemEncoding().decoder).join();
      final stderrFuture = process.stderr.transform(const SystemEncoding().decoder).join();
      final exitCodeFuture = process.exitCode;

      // 等待完成，带超时
      final results = await Future.wait([
        stdoutFuture,
        stderrFuture,
        exitCodeFuture,
      ]).timeout(
        Duration(milliseconds: _defaultTimeout),
        onTimeout: () {
          process.kill(ProcessSignal.sigterm);
          return ['', '命令执行超时 (${_defaultTimeout / 1000} 秒)', -1];
        },
      );

      final stdout = (results[0] as String).trim();
      final stderr = (results[1] as String).trim();
      final exitCode = results[2] as int;

      if (stdout.isNotEmpty) {
        parts.add(stdout);
      }
      if (stderr.isNotEmpty) {
        parts.add('[stderr]\n$stderr');
      }

      if (exitCode != 0) {
        parts.add('[退出码: $exitCode]');
      } else {
        parts.add('[退出码: 0]');
      }
    } catch (e) {
      parts.add('[错误] $e');
    }

    return parts.isEmpty ? '(无输出)' : parts.join('\n');
  },
);
