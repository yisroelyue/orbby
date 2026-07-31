// 工具：读取文件内容
// 从 orbby-agent/src/tools/read_file.ts 迁移

import 'dart:convert';
import 'dart:io';
import '../types.dart';

final readFileTool = ToolDefinition(
  name: 'read_file',
  description: '读取指定文件的内容。可以指定从第几行开始读（offset）和最多读多少行（limit）。返回带行号的内容。',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': '要读取的文件的完整路径'},
      'offset': {
        'type': 'integer',
        'description': '从第几行开始读取（1-based，默认从第 1 行开始）。例如 offset=10 则跳过前 9 行。',
      },
      'limit': {
        'type': 'integer',
        'description': '最多读取多少行（默认读取全部）。例如 limit=50 则最多返回 50 行。',
      },
    },
    'required': ['path'],
  },
  execute: (args) async {
    final filePath = args['path'] as String?;
    final offset = args['offset'] != null
        ? (args['offset'] as num).toInt().clamp(1, 999999)
        : 1;
    final limit = args['limit'] != null
        ? (args['limit'] as num).toInt().clamp(1, 999999)
        : null;

    if (filePath == null || filePath.isEmpty) {
      return '错误：path 参数无效';
    }

    final file = File(filePath);

    // 检查文件是否存在
    if (!file.existsSync()) {
      return '错误：文件不存在: $filePath';
    }

    // 检查是否是目录
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.directory) {
      return '错误：路径是目录而非文件: $filePath。如需查看目录结构，请使用 list_directory 工具。';
    }

    try {
      final content = file.readAsStringSync(encoding: utf8);
      final lines = content.split('\n');

      // 计算实际读取范围
      final startIdx = offset - 1;
      int endIdx = limit != null ? startIdx + limit : lines.length;
      if (endIdx > lines.length) endIdx = lines.length;

      if (startIdx >= lines.length) {
        return '文件共 ${lines.length} 行，offset=$offset 超出范围，没有内容可显示。';
      }

      // 格式化为带行号的内容
      final selectedLines = lines.sublist(startIdx, endIdx);
      final maxLineNum = endIdx;
      final padLen = maxLineNum.toString().length;

      final buffer = StringBuffer();
      for (int i = 0; i < selectedLines.length; i++) {
        final lineNum = (startIdx + i + 1).toString().padLeft(padLen);
        buffer.writeln('$lineNum │ ${selectedLines[i]}');
      }

      final rangeInfo = limit != null
          ? '（第 ${startIdx + 1}-$endIdx 行 / 共 ${lines.length} 行）'
          : '（共 ${lines.length} 行）';

      return '文件: $filePath $rangeInfo\n${buffer.toString().trimRight()}';
    } catch (e) {
      return '读取文件失败: $e';
    }
  },
);
