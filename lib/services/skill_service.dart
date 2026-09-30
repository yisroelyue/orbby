import 'dart:convert';
import 'dart:io';

import 'chat_skill.dart';

/// 技能库：扫描 ~/.orbby/skills/，两种形态（可混用）：
///
/// - 目录式（推荐，可带脚本/资源）：一个子目录一个技能，
///   元数据在 SKILL.md 的 frontmatter，同目录其余文件是技能资源
///   （脚本、模板等，由 Agent 按注入的目录路径自行取用）；
///   name 缺省用目录名。
/// - 散装单文件：一个 md 文件一个技能，name 缺省用文件名 stem。
///
/// 文件格式（frontmatter 只认 name/description 两个键，正文由 Node 侧
/// 加载注入，Flutter 不解析）：
///
///     ---
///     name: demo
///     description: 测试技能的说明
///     ---
///     技能正文（随 @ 引用注入 LLM 上下文）
///
/// 新增技能 = 在该目录加一个 SKILL.md 子目录或散装 md，无需改代码；
/// 目录不存在时创建并写入一个示例技能（首次运行 seed，供框架验证）。
class SkillService {
  static Directory get _skillsDir {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return Directory('$home/.orbby/skills');
  }

  /// 扫描技能目录并按名称排序返回；同名技能目录式优先（散装被覆盖）。
  /// 目录不可读等异常按空列表处理，不影响主界面启动。
  static Future<List<ChatSkill>> loadSkills() async {
    try {
      final dir = _skillsDir;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        await _seedDemoSkill(dir);
      }
      final loose = <String, ChatSkill>{};
      final dirBased = <String, ChatSkill>{};
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final skill = await _parseSkillFile(
            File('${entity.path}${Platform.pathSeparator}SKILL.md'),
            fallbackName: _stem(entity.path),
          );
          if (skill != null) dirBased[skill.name.toLowerCase()] = skill;
        } else if (entity is File &&
            entity.path.toLowerCase().endsWith('.md')) {
          final skill = await _parseSkillFile(
            entity,
            fallbackName: _stem(entity.path),
          );
          if (skill != null) loose[skill.name.toLowerCase()] = skill;
        }
      }
      // 展开顺序保证同名时目录式覆盖散装
      final byName = <String, ChatSkill>{...loose, ...dirBased};
      final skills = byName.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return skills;
    } catch (_) {
      return const <ChatSkill>[];
    }
  }

  /// 首次运行的示例技能：目录式形态（SKILL.md + 一个资源文件，验证清单
  /// 注入）；正文为可验证指令——Agent 收到后回复须带标记，肉眼即可确认生效
  static Future<void> _seedDemoSkill(Directory dir) async {
    const skill = '---\n'
        'name: demo\n'
        'description: 测试技能（框架验证用）\n'
        '---\n'
        '\n'
        '这是一个测试技能。收到本技能指令时，回复的第一行必须先是\n'
        '「【demo 技能已生效】」，然后再回答用户的实际问题。\n'
        '\n'
        '如用户询问本技能的资源，可读取技能目录下的 usage.txt。\n';
    const usage = 'demo 技能的资源文件：仅用于验证目录式技能的文件清单注入，\n'
        'Agent 应能在收到 @demo 引用时看到本文件名并按需读取。\n';
    final demoDir = Directory(
      '${dir.path}${Platform.pathSeparator}demo',
    );
    await demoDir.create(recursive: true);
    await File(
      '${demoDir.path}${Platform.pathSeparator}SKILL.md',
    ).writeAsString(skill, flush: true);
    await File(
      '${demoDir.path}${Platform.pathSeparator}usage.txt',
    ).writeAsString(usage, flush: true);
  }

  /// 解析单个技能文件的 frontmatter：name 优先取 frontmatter、缺省用
  /// [fallbackName]（目录式传目录名、散装传文件名 stem）；
  /// name 含空白字符的跳过（@ 引用片段以空白截止，无法被完整输入）。
  static Future<ChatSkill?> _parseSkillFile(
    File file, {
    required String fallbackName,
  }) async {
    try {
      final text = await file.readAsString(encoding: utf8);
      final meta = _parseFrontmatter(text);
      final name = (meta['name'] ?? '').trim().isNotEmpty
          ? (meta['name'] ?? '').trim()
          : fallbackName;
      if (name.isEmpty || RegExp(r'\s').hasMatch(name)) return null;
      return ChatSkill(
        name: name,
        description: (meta['description'] ?? '').trim(),
      );
    } catch (_) {
      // 单个文件解析失败跳过，不影响其余技能
      return null;
    }
  }

  /// 路径最后一段去扩展名（目录则就是目录名）
  static String _stem(String path) {
    final segments =
        path.split(Platform.pathSeparator).where((s) => s.isNotEmpty);
    final last = segments.isEmpty ? '' : segments.last;
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(0, dot) : last;
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
