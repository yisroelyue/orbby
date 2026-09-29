import 'dart:async';
import 'dart:io';

/// Starts the single Node runtime owned by the hidden hub window.
class AgentRuntimeProcess {
  AgentRuntimeProcess._();

  static Process? _process;
  static Future<void>? _starting;

  static Future<void> ensureStarted() =>
      _starting ??= _start().whenComplete(() => _starting = null);

  static Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process != null) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
      return;
    }
    await _killPortOwner();
  }

  static Future<void> _start() async {
    if (_process != null) return;
    final runtime = _runtimeDirectory();
    final entry = File('${runtime.path}${Platform.pathSeparator}dist${Platform.pathSeparator}main.js');
    if (!runtime.existsSync() || !entry.existsSync()) {
      stderr.writeln('Orbby agent runtime not found: ${entry.path}');
      return;
    }
    try {
      await _killPortOwner();
      final logFile = File('${Platform.environment['USERPROFILE'] ?? Directory.current.path}${Platform.pathSeparator}.orbby${Platform.pathSeparator}log${Platform.pathSeparator}agent-runtime.log');
      await logFile.parent.create(recursive: true);
      Future<void> append(String text) => logFile.writeAsString(text, mode: FileMode.append, flush: true);
      final process = await Process.start(
        Platform.isWindows ? 'node.exe' : 'node',
        [entry.path],
        workingDirectory: runtime.path,
      );
      _process = process;
      process.stdout.transform(SystemEncoding().decoder).listen(append);
      process.stderr.transform(SystemEncoding().decoder).listen(append);
      append('[Orbby] started agent runtime: ${entry.path}\n');
      process.exitCode.then((_) {
        if (identical(_process, process)) _process = null;
        append('[Orbby] agent runtime exited\n');
      });
    } on ProcessException catch (error) {
      stderr.writeln('Unable to start Orbby agent runtime: $error');
    }
  }

  static Future<void> _killPortOwner() async {
    if (!Platform.isWindows) return;
    final result = await Process.run('netstat', ['-ano', '-p', 'tcp']);
    final pattern = RegExp(r'^\s*TCP\s+127\.0\.0\.1:43127\s+\S+\s+LISTENING\s+(\d+)\s*$', multiLine: true);
    final pids = <int>{
      for (final match in pattern.allMatches(result.stdout.toString()))
        int.parse(match.group(1)!),
    };
    for (final processId in pids) {
      if (processId <= 0 || processId == pid) continue;
      await Process.run('taskkill', ['/PID', '$processId', '/T', '/F']);
    }
  }

  static Directory _runtimeDirectory() {
    final local = Directory('${Directory.current.path}${Platform.pathSeparator}agent-runtime');
    if (local.existsSync()) return local;
    return Directory('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}agent-runtime');
  }
}
