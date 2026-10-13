import 'dart:convert';
import 'dart:io';

/// `/cd` 工作区历史（MRU，最新在前），欢迎页「项目 / 工作区」续接的数据源。
///
/// 独立小文件持久化（~/.orbby/workspaces.json），刻意不挂在会话文件上：
/// 记录生命周期与会话无关（删会话不丢记录），且只有显式 /cd / 续接点击
/// 才记录，桌面默认工作区不会混进来。仅 menu 窗口 engine 读写（静态安全，
/// 同 MenuThemeService 模式）。
class WorkspaceHistoryService {
  WorkspaceHistoryService._();

  /// 存储上限（留余量，欢迎页展示条数由 UI 侧另行截取）
  static const maxEntries = 10;

  static Future<File> get _file async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/workspaces.json');
  }

  /// 读取历史（最新在前）；文件缺失/损坏返回空表。
  /// 顺带按忽略大小写去重（Windows 路径不区分大小写，防同一目录记两条）。
  static Future<List<String>> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final seen = <String>{};
      return [
        for (final entry in decoded)
          if (entry is String &&
              entry.isNotEmpty &&
              seen.add(entry.toLowerCase()))
            entry,
      ];
    } catch (_) {
      return [];
    }
  }

  /// 记录一次工作区切换：置顶去重、截断后落盘，返回更新后的列表（最新在前）。
  /// 连续快速 /cd 理论上可能交错写盘，最坏丢一条旧记录，MRU 场景可接受。
  static Future<List<String>> record(String path) async {
    final list = await load();
    list.removeWhere((e) => e.toLowerCase() == path.toLowerCase());
    list.insert(0, path);
    final capped = list.take(maxEntries).toList();
    try {
      final file = await _file;
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(capped),
      );
    } catch (_) {
      // 落盘失败不影响切换流程，内存列表照常返回
    }
    return capped;
  }
}
