import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/settings.dart';

/// 将运行日志写入 ~/.orbby/orbby.log。
///
/// 使用方式：
/// ```dart
/// LogService.init();                        // 在 main() 中尽早调用
/// LogService.info('App started');
/// LogService.error('Something broke', e, st, category: 'llm');
/// ```
///
/// 每个日志方法接受可选的 [category] 参数，对应设置中的日志分类
/// （system / llm），默认为 'system'。
/// 分类的输出开关由 [updateConfig] 动态设置。
class LogService {
  LogService._();

  static File? _file;
  static bool _initialized = false;
  static const _maxSize = 2 * 1024 * 1024; // 2 MB 轮转
  static final List<_PendingEntry> _pending = [];

  /// 当前日志分类配置（运行时由设置页同步）
  static Map<String, LogCategoryConfig> _config = {
    'system': const LogCategoryConfig(console: true, file: true),
    'llm': const LogCategoryConfig(console: true, file: false),
  };

  /// 更新运行时的日志分类配置（由设置保存后调用）
  static void updateConfig(Map<String, LogCategoryConfig> config) {
    _config = config.map(
      (k, v) => MapEntry(k, v),
    );
  }

  /// 获取指定分类的控制台开关状态
  static bool isConsoleEnabled(String category) {
    return _config[category]?.console ?? true;
  }

  /// 获取指定分类的文件开关状态
  static bool isFileEnabled(String category) {
    return _config[category]?.file ?? true;
  }

  /// 初始化日志文件。应在 [WidgetsFlutterBinding.ensureInitialized] 之后调用。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = Directory('${await _logDir()}/.orbby');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _file = File('${dir.path}/orbby.log');
      await _rotateIfNeeded();

      // 刷入初始化之前积压的消息
      for (final entry in _pending) {
        _writeLine(entry.line, category: entry.category);
      }
      _pending.clear();

      // 捕获未处理的 Flutter 异常
      PlatformDispatcher.instance.onError = (exception, stack) {
        error('Unhandled Flutter exception', exception: exception, stack: stack);
        return true; // 已处理，不再弹出系统对话框
      };
    } catch (_) {
      // 日志服务本身不应该导致崩溃
    }
  }

  /// 普通信息。
  static void info(String message, {String category = 'system'}) {
    _log('INFO', message, category: category);
  }

  /// 警告。
  static void warn(String message, {String category = 'system'}) {
    _log('WARN', message, category: category);
  }

  /// 错误，附带异常和堆栈。
  static void error(
    String message, {
    Object? exception,
    StackTrace? stack,
    String category = 'system',
  }) {
    final buf = StringBuffer(message);
    if (exception != null) {
      buf.write(' | exception: $exception');
    }
    if (stack != null) {
      buf.write('\n$stack');
    }
    _log('ERROR', buf.toString(), category: category);
  }

  /// 调试信息（仅控制台，不入文件）。
  static void debug(String message, {String category = 'system'}) {
    _log('DEBUG', message, category: category, fileOnly: false, consoleOnly: true);
  }

  // ---- 内部 ----

  static void _log(
    String level,
    String message, {
    String category = 'system',
    bool fileOnly = false,
    bool consoleOnly = false,
  }) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] [$level] $message';

    final cfg = _config[category] ?? const LogCategoryConfig();

    // 控制台输出
    if (!fileOnly && cfg.console) {
      debugPrint(line);
    }

    // 文件输出
    if (!consoleOnly && cfg.file) {
      if (_file == null) {
        _pending.add(_PendingEntry(line: line, category: category));
        if (_pending.length > 200) _pending.removeAt(0); // 防止无限积压
        return;
      }
      _writeLine(line, category: category);
    }
  }

  static void _writeLine(String line, {String category = 'system'}) {
    try {
      _file!.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // 静默失败，不阻塞主流程
    }
  }

  static Future<String> _logDir() async {
    try {
      return Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '.';
    } catch (_) {
      return '.';
    }
  }

  static Future<void> _rotateIfNeeded() async {
    try {
      if (_file == null) return;
      if (!await _file!.exists()) return;
      final len = await _file!.length();
      if (len >= _maxSize) {
        final backup = File('${_file!.path}.old');
        if (await backup.exists()) {
          await backup.delete();
        }
        await _file!.rename(backup.path);
      }
    } catch (_) {
      // 轮转失败不影响继续写入
    }
  }
}

class _PendingEntry {
  final String line;
  final String category;
  const _PendingEntry({required this.line, this.category = 'system'});
}
