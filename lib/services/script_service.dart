import 'dart:convert';
import 'dart:io';

import '../models/script_item.dart';

/// 脚本库服务
class ScriptService {
  ScriptService._();

  static String get _home =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '.';

  /// 脚本库目录 ~/.orbby/scriptLibrary
  static Future<Directory> _scriptDir() async {
    final dir = Directory('$_home/.orbby/scriptLibrary');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 脚本库设置文件 ~/.orbby/script_library.json
  static Future<File> _settingsFile() async {
    final dir = Directory('$_home/.orbby');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/script_library.json');
  }

  static Future<List<ScriptItem>> loadAll() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return [];
      return json
          .whereType<Map<String, dynamic>>()
          .map(ScriptItem.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<ScriptItem> scripts) async {
    final file = await _settingsFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(scripts.map((s) => s.toJson()).toList()),
    );
  }

  /// 从源文件添加脚本：读取头部注释元数据，复制到脚本库，保存到设置文件
  /// 注释读取失败抛出异常
  static Future<ScriptItem> addFromPath(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('文件不存在: $sourcePath');
    }

    final meta = await parseMetaFromFile(sourceFile);
    if (meta == null) {
      throw Exception('未在脚本头部找到元数据注释，无法添加');
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final fileName =
        sourcePath.split(RegExp(r'[\\/]')).last;

    final dir = await _scriptDir();
    final destPath = '${dir.path}/${id}_$fileName';
    await sourceFile.copy(destPath);

    final item = ScriptItem(
      id: id,
      name: meta.name,
      scriptPath: destPath,
      description: meta.description,
      params: meta.params,
    );

    final scripts = await loadAll();
    scripts.insert(0, item);
    await saveAll(scripts);
    return item;
  }

  /// 从脚本文件头部注释读取元数据，失败返回 null
  static Future<ScriptMeta?> parseMetaFromFile(File file) async {
    try {
      final content = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(100)
          .join('\n');
      return ScriptMeta.parse(content);
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String id) async {
    final scripts = await loadAll();
    final idx = scripts.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final removed = scripts.removeAt(idx);
    // 删除脚本库中的文件
    try {
      final f = File(removed.scriptPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await saveAll(scripts);
  }
}
