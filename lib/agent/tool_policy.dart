import 'dart:io';

class ToolPolicy {
  final String workspaceRoot;
  final bool allowCommandExecution;
  final bool allowDelete;
  final bool requireConfirmation;
  const ToolPolicy({
    required this.workspaceRoot,
    this.allowCommandExecution = true,
    this.allowDelete = true,
    this.requireConfirmation = false,
  });

  String? validate(String name, Map<String, dynamic> args) {
    if (name == 'execute_command' && !allowCommandExecution)
      return '命令执行已被安全策略禁止';
    if (name == 'delete_file' && !allowDelete) return '文件删除已被安全策略禁止';
    final path = args['path'] as String?;
    if (path != null && path.isNotEmpty && !_inside(path))
      return '路径超出工作区范围: $path';
    final cwd = args['cwd'] as String?;
    if (cwd != null && cwd.isNotEmpty && !_inside(cwd))
      return '命令工作目录超出工作区范围: $cwd';
    final lower = (args['command'] as String? ?? '').toLowerCase();
    if (name == 'execute_command' &&
        (RegExp(
              r'(^|[;&|])\s*(format|shutdown|reboot|diskpart)\b',
            ).hasMatch(lower) ||
            lower.contains('del /s') ||
            lower.contains('rm -rf') ||
            lower.contains('rmdir /s')))
      return '命令包含被禁止的高风险操作';
    if (requireConfirmation &&
        (name == 'delete_file' || name == 'execute_command'))
      return '该工具操作需要用户确认';
    return null;
  }

  bool _inside(String path) {
    try {
      final root = Directory(workspaceRoot).absolute.resolveSymbolicLinksSync();
      final type = FileSystemEntity.typeSync(path);
      final target = type == FileSystemEntityType.directory
          ? Directory(path).resolveSymbolicLinksSync()
          : File(path).absolute.parent.resolveSymbolicLinksSync();
      final prefix = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';
      final normalizedRoot = prefix.replaceAll('\\', '/').toLowerCase();
      final normalizedTarget = target.replaceAll('\\', '/').toLowerCase();
      return normalizedTarget == root.replaceAll('\\', '/').toLowerCase() ||
          normalizedTarget.startsWith(normalizedRoot);
    } catch (_) {
      return false;
    }
  }
}
