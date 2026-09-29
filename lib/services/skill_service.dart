import 'dart:convert';
import 'dart:io';

import 'chat_skill.dart';

/// 技能库：扫描 ~/.orbby/skills/ 下的 markdown 文件，一个文件一个技能。
///
/// 文件格式（frontmatter 只认 name/description 两个键，正文当前不解析）：
///
///     ---
///     name: demo
///     description: 测试技能的说明
///     ---
///     技能正文（发送链路生效时作为技能指令注入）
///
/// 新增技能 = 在该目录加一个 md 文件，无需改代码；目录不存在时
/// 创建并写入一个示例技能（首次运行 seed，供框架验证）。
class SkillService {
  static Directory get _skillsDir {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return Directory('$home/.orbby/skills');
  }

  /// 扫描技能目录并按名称排序返回；目录不可读等异常按空列表处理，
  /// 不影响主界面启动。
  static Future<List<ChatSkill>> loadSkills() async {
    try {
      final dir = _skillsDir;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        await _seedDemoSkill(dir);
      }
      final skills = <ChatSkill>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.md')) continue;
        final skill = await _parseSkillFile(entity);
        if (skill != null) skills.add(skill);
      }
      skills.sort((a, b) => a.name.compareTo(b.name));
      return skills;
    } catch (_) {
      return const <ChatSkill>[];
    }
  }

  /// 首次运行的示例技能：真实落盘（用户可编辑它验证扫描链路）
  static Future<void> _seedDemoSkill(Directory dir) async {
    const content = '---\n'
        'name: demo\n'
        'description: 测试技能（框架验证用）\n'
        '---\n'
        '\n'
        '这是一个测试技能。当前技能框架尚未接入发送链路：\n'
        '输入 @ 选中后仅在输入框插入 @demo 引用，随消息原样发送。\n';
    final file = File('${dir.path}${Platform.pathSeparator}demo.md');
    await file.writeAsString(content, flush: true);
  }

  /// 解析单个技能文件的 frontmatter：
  /// name 优先取 frontmatter、缺省用文件名（去扩展名）；
  /// name 含空白字符的文件跳过（@ 引用片段以空白截止，无法被正确输入）。
  static Future<ChatSkill?> _parseSkillFile(File file) async {
    try {
      final text = await file.readAsString(encoding: utf8);
      final meta = _parseFrontmatter(text);
      final fileName = file.uri.pathSegments.last;
      var name = (meta['name'] ?? '').trim();
      if (name.isEmpty) {
        final dot = fileName.lastIndexOf('.');
        name = dot > 0 ? fileName.substring(0, dot) : fileName;
      }
      if (name.isEmpty || RegExp(r'\s').hasMatch(name)) return null;
      return ChatSkill(
        name: name,
        description: (meta['description'] ?? '').trim(),
        fileName: fileName,
      );
    } catch (_) {
      // 单个文件解析失败跳过，不影响其余技能
      return null;
    }
  }

  /// 极简 frontmatter 解析：首行 '---' 到下一个 '---' 之间的 `key: value`
  static Map<String, String> _parseFrontmatter(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.first.trim() != '---') return const {};
    final meta = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim() == '---') break;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      meta[key] = value;
    }
    return meta;
  }
}
