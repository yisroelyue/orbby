// 工具：按文件名模式搜索文件（支持通配符）
// 从 orbby-agent/src/tools/search_files.ts 迁移

import 'dart:io';
import '../types.dart';

/// 将 glob 模式转换为正则表达式
/// ** → 匹配任意字符（包括路径分隔符）
/// *  → 匹配除路径分隔符外的任意字符
/// ?  → 匹配单个非路径分隔符
RegExp _globToRegex(String glob) {
  final buffer = StringBuffer();
  int i = 0;
  while (i < glob.length) {
    if (glob[i] == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
      // ** 匹配任意字符（包括路径分隔符）
      buffer.write('.*');
      i += 2;
      // 跳过后续的路径分隔符（**/ 和 ** 等价）
      if (i < glob.length && (glob[i] == '/' || glob[i] == '\\')) i++;
    } else if (glob[i] == '*') {
      // * 匹配除路径分隔符外的任意字符
      buffer.write('[^/\\\\]*');
      i++;
    } else if (glob[i] == '?') {
      buffer.write('[^/\\\\]');
      i++;
    } else if (glob[i] == '.') {
      buffer.write('\\.');
      i++;
    } else if (glob[i] == '\\' || glob[i] == '/') {
      buffer.write('[/\\\\]');
      i++;
    } else {
      // 普通字符，需要转义正则特殊字符
      const specials = '^\$+{}[]()|';
      if (specials.contains(glob[i])) {
        buffer.write('\\${glob[i]}');
      } else {
        buffer.write(glob[i]);
      }
      i++;
    }
  }
  return RegExp('^${buffer.toString()}\$', caseSensitive: false);
}

/// 跳过不应搜索的目录
const _skipDirs = {
  'node_modules',
  '.git',
  '.svn',
  '.hg',
  '__pycache__',
  '.idea',
  '.vscode',
  '.vs',
  'target',
  'build',
  'dist',
  '.next',
  '.nuxt',
  'vendor',
  'bower_components',
  '.cache',
  '.yarn',
};

bool _shouldSkipDir(String name) {
  return name.startsWith('.') || _skipDirs.contains(name);
}

/// 搜索结果
class _SearchResult {
  final String path;
  final String name;
  final int size;
  _SearchResult({required this.path, required this.name, required this.size});
}

/// 递归搜索匹配模式的文件
List<_SearchResult> _searchRecursive(
  String rootDir,
  RegExp regex,
  int maxResults,
  int currentDepth,
  int maxDepth,
) {
  final results = <_SearchResult>[];
  if (currentDepth > maxDepth) return results;

  List<FileSystemEntity> entries;
  try {
    entries = Directory(rootDir).listSync();
  } catch (_) {
    return results; // 无法访问的目录静默跳过
  }

  for (final entry in entries) {
    if (results.length >= maxResults) break;

    final name = entry.path.split(Platform.pathSeparator).last;

    if (entry is Directory) {
      if (_shouldSkipDir(name)) continue;
      results.addAll(
        _searchRecursive(
          entry.path,
          regex,
          maxResults - results.length,
          currentDepth + 1,
          maxDepth,
        ),
      );
    } else if (entry is File) {
      if (regex.hasMatch(name)) {
        int size = 0;
        try {
          size = entry.statSync().size;
        } catch (_) {}
        results.add(_SearchResult(path: entry.path, name: name, size: size));
      }
    }
  }

  return results;
}

/// 格式化搜索结果为文本
String _formatResults(
  List<_SearchResult> results,
  String rootDir,
  String pattern,
  int? elapsedMs,
) {
  if (results.isEmpty) {
    return '未找到匹配 "$pattern" 的文件\n搜索目录: $rootDir';
  }

  // 按目录分组
  final byDir = <String, List<_SearchResult>>{};
  for (final r in results) {
    final dir = r.path.substring(0, r.path.lastIndexOf(Platform.pathSeparator));
    byDir.putIfAbsent(dir, () => []).add(r);
  }

  final buffer = StringBuffer();
  buffer.writeln('找到 ${results.length} 个匹配 "$pattern" 的文件:');
  buffer.writeln('搜索目录: $rootDir');

  // 如果结果少，逐个显示；如果多，按目录汇总
  if (results.length <= 30) {
    for (final entry in byDir.entries) {
      buffer.writeln('\n📁 ${entry.key}/');
      for (final f in entry.value) {
        final sizeKB = (f.size / 1024).toStringAsFixed(1);
        buffer.writeln('   📄 ${f.name} ($sizeKB KB)');
      }
    }
  } else {
    // 结果很多时，只显示目录统计
    buffer.writeln('\n（结果较多，按目录汇总）:');
    for (final entry in byDir.entries) {
      buffer.writeln('   📁 ${entry.key}/ — ${entry.value.length} 个文件');
    }
  }

  if (elapsedMs != null) {
    buffer.writeln('\n⏱ 耗时: ${elapsedMs}ms');
  }

  return buffer.toString().trimRight();
}

final searchFilesTool = ToolDefinition(
  name: 'search_files',
  description:
      '按文件名模式搜索文件，支持通配符（* 和 **）。'
      '适合快速定位特定类型的文件，例如：\n'
      '- 搜索所有 Java 项目: pattern="**/pom.xml" 或 "**/build.gradle"\n'
      '- 搜索所有 JS 文件: pattern="**/*.js"\n'
      '- 搜索配置文件: pattern="**/*.config.js"\n'
      '会自动跳过 node_modules、.git、target、build 等无关目录，搜索深度限制 8 层。'
      '这是查找文件的最高效方式，应优先使用而非逐层扫描目录树。',
  parameters: {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': '搜索的起始目录。例如 C:\\Users\\yisro\\IdeaProjects 或用户主目录。',
      },
      'pattern': {
        'type': 'string',
        'description':
            '文件名匹配模式，支持通配符。* 匹配任意字符（不跨目录），** 匹配任意路径。'
            '例如: "**/pom.xml" 递归搜索所有 pom.xml，"*.js" 搜索所有 JS 文件，"**/Dockerfile" 搜索所有 Dockerfile。',
      },
      'max_results': {
        'type': 'integer',
        'description': '最多返回的结果数，默认 50。如果结果太多会被截断。',
      },
    },
    'required': ['path', 'pattern'],
  },
  execute: (args) async {
    final rootDir = args['path'] as String?;
    final pattern = args['pattern'] as String?;
    final maxResults = args['max_results'] != null
        ? (args['max_results'] as num).toInt().clamp(1, 200)
        : 50;

    if (rootDir == null || rootDir.isEmpty) {
      return '错误：path 参数无效，需要提供搜索起始目录';
    }
    if (pattern == null || pattern.isEmpty) {
      return '错误：pattern 参数无效，需要提供文件名匹配模式';
    }

    if (!Directory(rootDir).existsSync()) {
      return '错误：目录不存在: $rootDir';
    }

    final startTime = DateTime.now().millisecondsSinceEpoch;
    try {
      final regex = _globToRegex(pattern);
      final results = _searchRecursive(rootDir, regex, maxResults, 1, 8);
      final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
      return _formatResults(results, rootDir, pattern, elapsed);
    } catch (e) {
      return '搜索失败: $e';
    }
  },
);
