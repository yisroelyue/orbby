// 工具：编辑文件内容
// 从 orbby-agent/src/tools/edit_file.ts 迁移

import 'dart:convert';
import 'dart:io';
import '../types.dart';

final editFileTool = ToolDefinition(
  name: 'edit_file',
  description:
      '编辑已有文件的内容。支持三种模式：\n'
      '- replace: 将文件中的 old_string 替换为 new_string（默认模式，old_string 必须完全匹配）\n'
      '- append: 在文件末尾追加 new_string 内容\n'
      '- prepend: 在文件开头插入 new_string 内容',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': '要编辑的文件的完整路径'},
      'old_string': {
        'type': 'string',
        'description': '要被替换的原始字符串（仅 replace 模式需要，必须与文件中的内容完全一致）',
      },
      'new_string': {
        'type': 'string',
        'description':
            '要写入的新字符串。replace 模式下替换 old_string，append/prepend 模式下直接插入。',
      },
      'mode': {
        'type': 'string',
        'description': '编辑模式：replace（替换，默认）、append（末尾追加）、prepend（开头插入）',
        'enum': ['replace', 'append', 'prepend'],
      },
    },
    'required': ['path', 'new_string'],
  },
  execute: (args) async {
    final filePath = args['path'] as String?;
    final oldString = (args['old_string'] as String?) ?? '';
    final newString = args['new_string'] as String?;
    final mode = (args['mode'] as String?) ?? 'replace';

    if (filePath == null || filePath.isEmpty) {
      return '错误：path 参数无效';
    }
    if (newString == null) {
      return '错误：new_string 参数无效，需要提供字符串内容';
    }

    final file = File(filePath);

    // 检查文件是否存在
    if (!file.existsSync()) {
      return '错误：文件不存在: $filePath。如需创建新文件，请使用 create_file 工具。';
    }

    // 检查是否是目录
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.directory) {
      return '错误：路径是目录而非文件: $filePath';
    }

    try {
      final originalContent = file.readAsStringSync(encoding: utf8);

      String newContent;
      String actionDesc;

      switch (mode) {
        case 'append':
          newContent = originalContent + newString;
          actionDesc = '末尾追加';
          break;

        case 'prepend':
          newContent = newString + originalContent;
          actionDesc = '开头插入';
          break;

        case 'replace':
        default:
          {
            if (oldString.isEmpty) {
              return '错误：replace 模式需要提供 old_string 参数';
            }
            // 检查 old_string 是否存在
            final index = originalContent.indexOf(oldString);
            if (index == -1) {
              return '错误：在文件中未找到要替换的内容。请确保 old_string 与文件中的内容完全一致（包括空格和换行）。';
            }
            // 检查 old_string 是否唯一
            final secondIndex = originalContent.indexOf(oldString, index + 1);
            if (secondIndex != -1) {
              return '错误：old_string 在文件中出现了多次，无法确定要替换哪一处。请提供更长的上下文使其唯一。';
            }
            newContent = originalContent.replaceFirst(oldString, newString);
            actionDesc = '替换';
            break;
          }
      }

      file.writeAsStringSync(newContent, encoding: utf8);

      final origSize = originalContent.length;
      final newSize = newContent.length;
      final diff = newSize - origSize;
      final diffStr = diff >= 0 ? '+$diff' : '$diff';

      return '文件已成功$actionDesc: $filePath\n原始大小: $origSize 字符 → 新大小: $newSize 字符 ($diffStr 字符)';
    } catch (e) {
      return '编辑文件失败: $e';
    }
  },
);
