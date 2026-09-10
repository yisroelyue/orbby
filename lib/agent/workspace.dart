import 'dart:io';

/// Agent 的工作目录：默认为用户桌面，首次使用前自动获取真实桌面路径。
/// Windows 桌面可能被 OneDrive 重定向，因此优先读注册表里的实际路径。
class AgentWorkspace {
  AgentWorkspace._();

  static String? _resolved;

  /// 当前工作目录（同步访问）。尚未解析完成时返回快速回退值
  /// （USERPROFILE\Desktop，拿不到主目录则退回进程目录）。
  static String get current {
    final resolved = _resolved;
    if (resolved != null) return resolved;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (home.isEmpty) return Directory.current.path;
    return Platform.isWindows ? '$home\\Desktop' : '$home/Desktop';
  }

  /// 解析真实桌面路径并缓存；Agent 创建前应先 await 一次。
  /// Windows 读注册表 Explorer\Shell Folders\Desktop（已是展开后的实际路径）。
  static Future<void> resolve() async {
    if (_resolved != null) return;
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
          '/v',
          'Desktop',
        ]);
        final match = RegExp(
          r'REG_SZ\s+(.+)$',
          multiLine: true,
        ).firstMatch(result.stdout.toString());
        final path = match?.group(1)?.trim();
        if (path != null && path.isNotEmpty && Directory(path).existsSync()) {
          _resolved = path;
          return;
        }
      }
      _resolved = current;
    } catch (_) {
      // 解析失败时保持回退值
    }
  }
}
