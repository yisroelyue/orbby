import 'dart:convert';
import 'dart:io';

class PersonalityService {
  PersonalityService._();

  static const presets = <String, String>{
    'humor': '风格幽默，可以使用适量网络热词热梗；不刻意讨好，保持自己的性格。',
    'serious': '严谨、专业、克制，避免玩梗。',
    'concise': '简洁直接，优先给出结论，避免冗余。',
  };

  /// 解析性格输入：精确名 > 唯一前缀匹配（如 h→humor、se→serious）。
  /// 返回 (命中 key, 候选列表)：无命中或前缀歧义（多候选）时 key 为 null，
  /// candidates 供上层提示。
  static (String?, List<String>) resolve(String input) {
    final key = input.trim().toLowerCase();
    if (presets.containsKey(key)) return (key, const <String>[]);
    final matches = presets.keys.where((name) => name.startsWith(key)).toList()
      ..sort();
    return matches.length == 1
        ? (matches.single, const <String>[])
        : (null, matches);
  }

  static Future<File> _file() async {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    final dir = Directory('$home/.orbby/setting');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/personality.json');
  }

  static Future<String> load() async {
    try {
      final json = jsonDecode(await (await _file()).readAsString()) as Map<String, dynamic>;
      final value = json['name']?.toString() ?? 'humor';
      return presets.containsKey(value) ? value : 'humor';
    } catch (_) { return 'humor'; }
  }

  static Future<void> save(String name) async {
    await (await _file()).writeAsString(jsonEncode({'name': name}));
  }
}
