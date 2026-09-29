import 'dart:convert';
import 'dart:io';

import '../theme/chat_theme.dart';

/// menu 窗口主题偏好持久化：独立小文件，避免与设置页的
/// orbby_settings.json 读写互相踩（两个 engine 可能同时写）。
class MenuThemeService {
  MenuThemeService._();

  static bool _cached = false;
  static bool _dark = true;

  static Future<File> _file() async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby/setting');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/menu_theme.json');
  }

  /// 启动时读取一次（默认深色，延续旧版观感）；之后只信任内存值
  static Future<bool> load() async {
    if (_cached) return _dark;
    _cached = true;
    try {
      final file = await _file();
      if (!await file.exists()) return _dark;
      final json = jsonDecode(await file.readAsString());
      _dark = (json is Map && json['theme'] == 'light') ? false : true;
    } catch (_) {}
    return _dark;
  }

  static Future<void> save(bool dark) async {
    _dark = dark;
    _cached = true;
    try {
      final file = await _file();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({'theme': dark ? 'dark' : 'light'}),
      );
    } catch (_) {}
  }

  /// 供设置页等其他窗口读取当前偏好（只读，不缓存覆盖）
  static Future<ChatThemeData> loadThemeData() async {
    final dark = await load();
    return dark ? ChatThemeData.dark : ChatThemeData.light;
  }
}
