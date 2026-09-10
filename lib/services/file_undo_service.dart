import 'dart:convert';
import 'dart:io';

/// agent 文件改动备份：写类工具执行前记录原内容，/rollback 还原最近一次。
///
/// 只在 menu 窗口 engine 内使用（工具执行与 /rollback 命令同处一个 engine，
/// 静态缓存安全）；IO 与 agent 工具保持一致用同步 API。
/// 边界：目录删除不做备份（体积不可控），/rollback 覆盖不到。
class FileUndoService {
  FileUndoService._();

  /// 最多保留的记录数，超出淘汰最旧（连同其备份文件）
  static const _maxRecords = 50;

  /// manifest 缓存；null = 未从磁盘加载
  static List<Map<String, dynamic>>? _records;

  static Directory get _dir {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return Directory('$home/.orbby/undo');
  }

  static File get _manifestFile => File('${_dir.path}/manifest.json');

  static List<Map<String, dynamic>> get _recordList {
    if (_records != null) return _records!;
    try {
      final file = _manifestFile;
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        _records = (decoded as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _records = [];
      }
    } catch (_) {
      _records = [];
    }
    return _records!;
  }

  static void _flush() {
    try {
      _dir.createSync(recursive: true);
      _manifestFile.writeAsStringSync(jsonEncode(_recordList));
    } catch (_) {
      // 记录写失败不阻塞工具本身
    }
  }

  /// 修改/覆盖文件前调用（edit_file、create_file 的 overwrite）：备份原内容
  static void recordEdit(String path) => _backup(path, 'edit');

  /// 新建文件前调用（create_file）：回滚 = 删除该文件
  static void recordCreate(String path) => _record(path, 'create', null);

  /// 删除文件前调用：备份内容，回滚 = 恢复
  static void recordDelete(String path) => _backup(path, 'delete');

  static void _backup(String path, String type) {
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      _dir.createSync(recursive: true);
      // 字节级复制，二进制文件也能还原
      final backupPath =
          '${_dir.path}/undo_${DateTime.now().microsecondsSinceEpoch}.bin';
      file.copySync(backupPath);
      _record(path, type, backupPath);
    } catch (_) {
      // 备份失败不阻塞工具本身
    }
  }

  static void _record(String path, String type, String? backupPath) {
    final records = _recordList;
    records.add({
      'path': path,
      'type': type,
      if (backupPath != null) 'backup': backupPath,
      'time': DateTime.now().toIso8601String(),
    });
    while (records.length > _maxRecords) {
      final oldest = records.removeAt(0);
      _deleteBackupFile(oldest['backup'] as String?);
    }
    _flush();
  }

  /// 还原最近一次改动，返回结果描述（直接作为聊天消息展示）
  static String undoLast() {
    final records = _recordList;
    if (records.isEmpty) return '没有可回滚的文件改动。';
    final rec = records.removeLast();
    _flush();

    final path = rec['path'] as String? ?? '';
    final type = rec['type'] as String? ?? '';
    final backupPath = rec['backup'] as String?;
    var restored = false;
    String result;
    try {
      switch (type) {
        case 'edit':
          result = _restore(backupPath, path, '已回滚文件修改');
          restored = !result.startsWith('回滚失败');
          break;
        case 'create':
          final file = File(path);
          if (file.existsSync()) file.deleteSync();
          result = '已回滚（删除新建文件）: $path';
          restored = true;
          break;
        case 'delete':
          result = _restore(backupPath, path, '已恢复被删除的文件');
          restored = !result.startsWith('回滚失败');
          break;
        default:
          result = '回滚失败：未知的改动类型（$path）。';
      }
    } catch (e) {
      result = '回滚失败: $e';
    }
    // 还原成功才清理备份；失败时保留以供排查/重试
    if (restored) _deleteBackupFile(backupPath);
    return result;
  }

  static String _restore(String? backupPath, String path, String okLabel) {
    if (backupPath == null || !File(backupPath).existsSync()) {
      return '回滚失败：备份内容丢失（$path）。';
    }
    File(path).writeAsBytesSync(File(backupPath).readAsBytesSync());
    return '$okLabel: $path';
  }

  static void _deleteBackupFile(String? backupPath) {
    if (backupPath == null) return;
    try {
      final f = File(backupPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
