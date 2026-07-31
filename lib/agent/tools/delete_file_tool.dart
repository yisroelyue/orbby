// 工具：删除文件或目录
// 从 orbby-agent/src/tools/delete_file.ts 迁移

import 'dart:io';
import '../types.dart';

final deleteFileTool = ToolDefinition(
  name: 'delete_file',
  description: '删除指定的文件或目录。删除目录时需要设置 recursive 为 true，否则只删除空目录。操作不可逆，请谨慎使用。',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': '要删除的文件或目录的完整路径'},
      'recursive': {
        'type': 'boolean',
        'description': '删除目录时是否递归删除其所有内容。默认为 false，即只删除空目录。',
      },
    },
    'required': ['path'],
  },
  execute: (args) async {
    final targetPath = args['path'] as String?;
    final recursive = args['recursive'] == true;

    if (targetPath == null || targetPath.isEmpty) {
      return '错误：path 参数无效，需要提供有效的路径字符串';
    }

    final entity = FileSystemEntity.typeSync(targetPath);

    // 检查是否存在
    if (entity == FileSystemEntityType.notFound) {
      return '错误：路径不存在: $targetPath';
    }

    try {
      if (entity == FileSystemEntityType.directory) {
        final dir = Directory(targetPath);
        if (recursive) {
          dir.deleteSync(recursive: true);
          return '已递归删除目录: $targetPath';
        } else {
          dir.deleteSync();
          return '已删除空目录: $targetPath';
        }
      } else {
        final file = File(targetPath);
        final sizeKB = (file.statSync().size / 1024).toStringAsFixed(2);
        file.deleteSync();
        return '已删除文件: $targetPath (原大小: $sizeKB KB)';
      }
    } catch (e) {
      if (e is FileSystemException && e.osError?.errorCode == 145) {
        // ENOTEMPTY on Windows
        return '错误：目录不为空，无法删除: $targetPath\n提示：如需递归删除，请设置 recursive 为 true';
      }
      return '删除失败: $e';
    }
  },
);
