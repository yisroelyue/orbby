import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 将运行日志写入 ~/.orbby/orbby.log。
///
/// 使用方式：
/// ```dart
/// LogService.init();                        // 在 main() 中尽早调用
/// LogService.info('App started');
/// LogService.warn('Something suspicious');
/// LogService.error('Something broke', e, st);
/// ```
class LogService {
  LogService._();

  static File? _file;
  static bool _initialized = false;
  static const _maxSize = 2 * 1024 * 1024; // 2 MB 轮转
  static final List<String> _pending = [];

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
      for (final msg in _pending) {
        _writeLine(msg);
      }
      _pending.clear();

      // 捕获未处理的 Flutter 异常
      PlatformDispatcher.instance.onError = (exception, stack) {
        error('Unhandled Flutter exception', exception, stack);
        return true; // 已处理，不再弹出系统对话框
      };
    } catch (_) {
      // 日志服务本身不应该导致崩溃
    }
  }

  /// 普通信息。
  static void info(String message) {
    _log('INFO', message);
  }

  /// 警告。
  static void warn(String message) {
    _log('WARN', message);
  }

  /// 错误，附带异常和堆栈。
  static void error(String message, [Object? exception, StackTrace? stack]) {
    final buf = StringBuffer(message);
    if (exception != null) {
      buf.write(' | exception: $exception');
    }
    if (stack != null) {
      buf.write('\n$stack');
    }
    _log('ERROR', buf.toString());
  }

  // ---- 内部 ----

  static void _log(String level, String message) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] [$level] $message';

    // 同时输出到控制台（flutter run 调试终端可见）
    debugPrint(line);

    if (_file == null) {
      _pending.add(line);
      if (_pending.length > 200) _pending.removeAt(0); // 防止无限积压
      return;
    }

    _writeLine(line);
  }

  static void _writeLine(String line) {
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
