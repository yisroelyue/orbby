// 工具：列出目录结构
// 从 orbby-agent/src/tools/list_directory.ts 迁移

import 'dart:io';
import '../types.dart';

/// 目录项
class _DirectoryEntry {
  final String name;
  final String type; // 'dir' or 'file'
  _DirectoryEntry({required this.name, required this.type});
}

/// 目录树节点
class _TreeNode {
  final String name;
  final String? path;
  final String type;
  final List<_TreeNode> children;
  final String? error;

  _TreeNode({
    required this.name,
    this.path,
    required this.type,
    List<_TreeNode>? children,
    this.error,
  }) : children = children ?? [];
}

/// 获取用户主目录
String _homeDir() {
  if (Platform.isWindows) {
    return Platform.environment['USERPROFILE'] ?? 'C:\\Users\\default';
  }
  return Platform.environment['HOME'] ?? '/home';
}

/// 获取桌面目录
String _desktopDir() {
  final home = _homeDir();
  final candidates = [
    '$home${Platform.pathSeparator}Desktop',
    '$home${Platform.pathSeparator}桌面',
  ];
  for (final c in candidates) {
    if (Directory(c).existsSync()) return c;
  }
  return '$home${Platform.pathSeparator}Desktop';
}

/// 获取指定目录的子目录和文件列表
Map<String, dynamic> _listDir(String dirPath, {int maxItems = 50}) {
  try {
    final dir = Directory(dirPath);
    final entries = dir.listSync();
    final dirs = <_DirectoryEntry>[];
    final files = <_DirectoryEntry>[];

    for (final entry in entries) {
      final name = entry.path.split(Platform.pathSeparator).last;
      // 跳过隐藏文件/目录（以 . 开头）
      if (name.startsWith('.')) continue;

      if (entry is Directory) {
        dirs.add(_DirectoryEntry(name: name, type: 'dir'));
      } else if (entry is File) {
        files.add(_DirectoryEntry(name: name, type: 'file'));
      }
    }

    // 排序：目录在前，文件在后，各自按字母排序
    dirs.sort((a, b) => a.name.compareTo(b.name));
    files.sort((a, b) => a.name.compareTo(b.name));

    final result = [...dirs, ...files];
    final truncated = result.length > maxItems;
    return {
      'items': result.take(maxItems).toList(),
      'total': result.length,
      'truncated': truncated,
    };
  } catch (e) {
    return {'error': e.toString()};
  }
}

/// 递归获取目录树（限制深度和每层数量）
_TreeNode? _getTree(String dirPath, int depth, int maxDepth, int maxPerLevel) {
  if (depth > maxDepth) return null;

  final result = _listDir(dirPath, maxItems: maxPerLevel);
  if (result.containsKey('error')) {
    return _TreeNode(
      name: dirPath.split(Platform.pathSeparator).last,
      type: 'dir',
      error: result['error'] as String,
    );
  }

  final items = result['items'] as List<_DirectoryEntry>;
  final node = _TreeNode(
    name: dirPath.split(Platform.pathSeparator).last,
    path: dirPath,
    type: 'dir',
  );

  for (final item in items) {
    if (item.type == 'dir' && depth < maxDepth) {
      final child = _getTree(
        '$dirPath${Platform.pathSeparator}${item.name}',
        depth + 1,
        maxDepth,
        maxPerLevel,
      );
      if (child != null) node.children.add(child);
    } else if (item.type == 'dir') {
      node.children.add(_TreeNode(
        name: item.name,
        path: '$dirPath${Platform.pathSeparator}${item.name}',
        type: 'dir',
      ));
    } else {
      // 文件在所有深度都列出，每层最多 15 个文件
      final fileCount = node.children.where((c) => c.type == 'file').length;
      if (fileCount < 15) {
        node.children.add(_TreeNode(
          name: item.name,
          path: '$dirPath${Platform.pathSeparator}${item.name}',
          type: 'file',
        ));
      }
    }
  }

  return node;
}

/// 将树结构格式化为文本输出
String _formatTree(_TreeNode node, String indent, bool isLast, String rootLabel) {
  final buffer = StringBuffer();

  if (rootLabel.isNotEmpty) {
    buffer.writeln(rootLabel);
  } else {
    final prefix = indent + (isLast ? '└── ' : '├── ');
    final icon = node.type == 'dir' ? '📁' : '📄';
    final extra = node.error != null ? ' (无法访问: ${node.error})' : '';
    buffer.writeln('$prefix$icon ${node.name}$extra');
  }

  if (node.children.isNotEmpty) {
    final newIndent = rootLabel.isNotEmpty ? indent : indent + (isLast ? '    ' : '│   ');
    for (int i = 0; i < node.children.length; i++) {
      final childIsLast = i == node.children.length - 1;
      buffer.write(_formatTree(node.children[i], newIndent, childIsLast, ''));
    }
  }

  return buffer.toString();
}

final listDirectoryTool = ToolDefinition(
  name: 'list_directory',
  description: '列出目录结构，以树形展示文件和子目录。可以查看指定路径的目录树，也可以查看系统常用目录（桌面、文档、下载、用户主目录）。\n'
      'depth 控制查看深度（默认 2 层），每层最多显示 30 个条目。适合用于了解目录层级结构，而非列出所有文件。',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': '要查看的目录路径。如果不填，则显示系统常用目录概览（用户主目录、桌面、文档、下载等）。可以填入具体路径来查看该目录的子树。',
      },
      'depth': {
        'type': 'integer',
        'description': '目录树深度，默认为 2。1=只显示当前目录内容，2=显示当前目录及一级子目录，以此类推。最大 4 层。',
      },
    },
    'required': [],
  },
  execute: (args) async {
    final targetPath = args['path'] as String?;
    final depth = args['depth'] != null
        ? (args['depth'] as num).toInt().clamp(1, 4)
        : 2;

    // 情况 1：没有指定路径，显示系统常用目录概览
    if (targetPath == null || targetPath.isEmpty) {
      final sections = [
        {'key': '用户主目录', 'path': _homeDir()},
        {'key': '桌面', 'path': _desktopDir()},
        {'key': '文档', 'path': '${_homeDir()}${Platform.pathSeparator}Documents'},
        {'key': '下载', 'path': '${_homeDir()}${Platform.pathSeparator}Downloads'},
      ];

      final buffer = StringBuffer();
      buffer.writeln('=== 系统目录概览 ===\n');

      for (final section in sections) {
        final dirPath = section['path'] as String;
        final dir = Directory(dirPath);
        buffer.writeln('【${section['key']}】${dir.existsSync() ? '' : ' (不存在)'}');
        buffer.writeln('路径: $dirPath');

        if (dir.existsSync()) {
          final tree = _getTree(dirPath, 1, depth, 30);
          if (tree != null) {
            buffer.write(_formatTree(tree, '', true, ''));
          }
        }
        buffer.writeln();
      }

      // Windows：额外列出常见盘符
      if (Platform.isWindows) {
        buffer.writeln('【可用盘符】');
        for (int d = 65; d <= 90; d++) {
          final drive = '${String.fromCharCode(d)}:\\';
          if (Directory(drive).existsSync()) {
            try {
              final rootList = _listDir(drive, maxItems: 10);
              if (rootList.containsKey('items')) {
                final dirNames = (rootList['items'] as List<_DirectoryEntry>)
                    .where((i) => i.type == 'dir')
                    .map((i) => i.name)
                    .join(', ');
                buffer.writeln('  $drive ${dirNames.isNotEmpty ? '→ $dirNames' : '(空或无法访问)'}');
              }
            } catch (_) {
              // skip
            }
          }
        }
        buffer.writeln();
      }

      return buffer.toString().trimRight();
    }

    // 情况 2：指定了路径，显示该路径的目录树
    if (!Directory(targetPath).existsSync()) {
      // 检查是否是文件
      if (File(targetPath).existsSync()) {
        final parentDir = File(targetPath).parent.path;
        final tree = _getTree(parentDir, 1, (depth - 1).clamp(1, 4), 30);
        return '路径是文件而非目录，显示其所在目录:\n\n${tree != null ? _formatTree(tree, '', true, '') : ''}';
      }
      return '错误：路径不存在: $targetPath';
    }

    final tree = _getTree(targetPath, 1, depth, 30);
    if (tree == null) {
      return '无法读取目录: $targetPath';
    }

    return '目录树: $targetPath（深度 $depth 层）\n\n${_formatTree(tree, '', true, '')}';
  },
);
