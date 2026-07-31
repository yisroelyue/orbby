// 工具：创建文件并写入内容
// 从 orbby-agent/src/tools/create_file.ts 迁移

import 'dart:convert';
import 'dart:io';
import '../types.dart';

final createFileTool = ToolDefinition(
  name: 'create_file',
  description:
      '在指定路径创建文件并写入内容。如果目录不存在会自动创建。默认不会覆盖已存在的文件，除非设置 overwrite 为 true。',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': '要创建的文件的完整路径，例如 C:\\Users\\username\\Desktop\\hello.txt',
      },
      'content': {'type': 'string', 'description': '要写入文件的内容'},
      'overwrite': {
        'type': 'boolean',
        'description': '是否覆盖已存在的文件，默认为 false。设为 true 才会覆盖已有文件。',
      },
    },
    'required': ['path', 'content'],
  },
  execute: (args) async {
    final filePath = args['path'] as String?;
    final content = args['content'] as String?;
    final overwrite = args['overwrite'] == true;

    if (filePath == null || filePath.isEmpty) {
      return '错误：path 参数无效，需要提供有效的文件路径字符串';
    }
    if (content == null) {
      return '错误：content 参数无效，需要提供字符串内容';
    }

    final file = File(filePath);

    // 检查文件是否已存在
    if (file.existsSync() && !overwrite) {
      return '文件已存在，未覆盖: $filePath\n提示：如需覆盖，请设置 overwrite 为 true';
    }

    try {
      // 确保目录存在
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // 写入文件
      file.writeAsStringSync(content, encoding: utf8);

      // 获取文件大小
      final stat = file.statSync();
      final sizeKB = (stat.size / 1024).toStringAsFixed(2);

      final action = (overwrite && file.existsSync()) ? '覆盖并更新' : '创建';
      return '文件已成功$action: $filePath\n大小: $sizeKB KB (${stat.size} 字节)';
    } catch (e) {
      return '创建文件失败: $e';
    }
  },
);
