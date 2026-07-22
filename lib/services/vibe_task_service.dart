import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum VibeTaskStatus {
  working,
  needsApproval,
  needsInput,
  idle,
  completed,
  failed,
  stopped;

  String get label {
    switch (this) {
      case VibeTaskStatus.working:
        return '执行中';
      case VibeTaskStatus.needsApproval:
        return '等待确认';
      case VibeTaskStatus.needsInput:
        return '等待输入';
      case VibeTaskStatus.idle:
        return '空闲';
      case VibeTaskStatus.completed:
        return '已完成';
      case VibeTaskStatus.failed:
        return '失败';
      case VibeTaskStatus.stopped:
        return '已停止';
    }
  }

  static VibeTaskStatus fromString(String s) {
    final normalized = s
        .trim()
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .toLowerCase();
    switch (normalized) {
      case 'working':
      case 'running':
      case 'busy':
      case 'using_tool':
      case 'usingtool':
        return VibeTaskStatus.working;
      case 'needsapproval':
      case 'needs_approval':
      case 'waiting_approval':
      case 'waiting_confirmation':
      case 'waitingconfirmation':
      case 'permission_prompt':
      case 'approval_needed':
        return VibeTaskStatus.needsApproval;
      case 'needsinput':
      case 'needs_input':
      case 'waiting_input':
      case 'waitinginput':
      case 'input_needed':
      case 'blocked':
        return VibeTaskStatus.needsInput;
      case 'completed':
      case 'complete':
      case 'done':
      case 'idle_completed':
        return VibeTaskStatus.completed;
      case 'failed':
      case 'failure':
      case 'error':
        return VibeTaskStatus.failed;
      case 'stopped':
      case 'stop':
      case 'cancelled':
      case 'canceled':
        return VibeTaskStatus.stopped;
      case 'idle':
      default:
        return VibeTaskStatus.idle;
    }
  }
}

class VibeTask {
  const VibeTask({
    required this.sessionId,
    required this.name,
    required this.status,
    this.timestamp,
    this.cwd,
    this.eventName,
    this.message,
    this.toolName,
  });

  final String sessionId;
  final String name;
  final VibeTaskStatus status;
  final int? timestamp;
  final String? cwd;
  final String? eventName;
  final String? message;
  final String? toolName;

  String get projectName {
    if (cwd != null && cwd!.isNotEmpty) {
      final parts = cwd!.replaceAll('\\', '/').split('/');
      return parts.lastWhere((p) => p.isNotEmpty, orElse: () => name);
    }
    if (name.isNotEmpty) return name;
    return sessionId;
  }

  String get actionLabel {
    if (toolName != null && toolName!.isNotEmpty) return toolName!;
    if (eventName != null && eventName!.isNotEmpty) return eventName!;
    return '';
  }
}

typedef VibeTaskList = List<VibeTask>;

class VibeTaskService {
  VibeTaskService._();

  static final instance = VibeTaskService._();

  final _tasks = <String, VibeTask>{};
  final _notifier = ValueNotifier<VibeTaskList>(const []);
  ValueNotifier<VibeTaskList> get notifier => _notifier;

  VibeTaskList get tasks => _notifier.value;

  static final _fileNamePattern = RegExp(r'^vibe_task_(.+)\.json$');
  static final _signalPattern = RegExp(r'^vibe_task_(.+)\.signal$');

  StreamSubscription? _watchSub;
  Timer? _debounceTimer;
  Timer? _cleanupTimer;

  // Completed / failed / stopped tasks hang around for this long before removal.
  static const _doneVisibilityMs = 30 * 1000; // 30 seconds
  // Any task that hasn't been updated in this long is considered stale (crashed).
  static const _staleTaskMs = 10 * 60 * 1000; // 10 minutes

  Directory get _stateDirectory {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return Directory('$home/.orbby/claude_task');
  }

  void start() {
    stop();
    _ensureStateDirectory();
    _removeStaleFiles(); // clean up stale files immediately on startup
    _readAllFiles();
    _startWatching();
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        _removeStaleFiles();
        _publish(); // reap finished tasks whose visibility window expired
      },
    );
  }

  void stop() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _watchSub?.cancel();
    _watchSub = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  // ---------------------------------------------------------------------------
  // File-system watching
  // ---------------------------------------------------------------------------

  void _startWatching() {
    _watchSub?.cancel();

    // Prefer watching the directory so we pick up new sessions whose files
    // don't exist yet.
    try {
      _watchSub = _stateDirectory.watch().listen(
        _onDirectoryEvent,
        onError: (error) {
          debugPrint('Vibe task directory watcher error: $error');
        },
      );
    } catch (error) {
      debugPrint('Failed to start directory watcher: $error');
    }
  }

  void _onDirectoryEvent(FileSystemEvent event) {
    final name = event.path.replaceAll('\\', '/').split('/').last;
    if (_fileNamePattern.hasMatch(name)) {
      _scheduleRead();
    }
  }

  // ---------------------------------------------------------------------------
  // Debounced read
  // ---------------------------------------------------------------------------

  void _scheduleRead() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), _readAllFiles);
  }

  // ---------------------------------------------------------------------------
  // Read all task files (only for files that changed)
  // ---------------------------------------------------------------------------

  void _readAllFiles() {
    try {
      final dir = _stateDirectory;
      if (!dir.existsSync()) return;

      for (final file in dir.listSync()) {
        if (file is! File) continue;
        final name = file.uri.pathSegments.last;
        final match = _fileNamePattern.firstMatch(name);
        if (match == null) continue;

        final sessionId = match.group(1)!;
        final task = _parseFile(file, sessionId);
        if (task != null) {
          _tasks[sessionId] = task;
        }
      }

      _publish();
    } catch (error) {
      debugPrint('Vibe task read error: $error');
    }
  }

  VibeTask? _parseFile(File file, String sessionId) {
    try {
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return null;

      final json = jsonDecode(content) as Map<String, dynamic>;
      return VibeTask(
        sessionId: sessionId,
        name: json['name'] as String? ?? '',
        status: VibeTaskStatus.fromString(json['status'] as String? ?? 'idle'),
        timestamp: _asInt(json['timestamp']),
        cwd: json['cwd'] as String?,
        eventName: json['eventName'] as String?,
        message: json['message'] as String?,
        toolName: json['toolName'] as String?,
      );
    } on FileSystemException {
      // File disappeared between list and read — ignore.
      return null;
    } catch (error) {
      debugPrint('Failed to parse task file: $error');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Publish + reap finished tasks
  // ---------------------------------------------------------------------------

  void _publish() {
    final now = DateTime.now().millisecondsSinceEpoch;

    final toRemove = <String>{};
    _tasks.forEach((sessionId, task) {
      if (task.timestamp == null) return;
      final age = now - task.timestamp!;

      // Always expire stale tasks (crashed sessions that never sent Stop).
      if (age > _staleTaskMs) {
        toRemove.add(sessionId);
        return;
      }

      // Remove finished tasks after the visibility window.
      switch (task.status) {
        case VibeTaskStatus.completed:
        case VibeTaskStatus.failed:
        case VibeTaskStatus.stopped:
          if (age > _doneVisibilityMs) {
            toRemove.add(sessionId);
          }
        default:
          break;
      }
    });

    // Delete files for removed tasks so they don't accumulate on disk.
    for (final sessionId in toRemove) {
      _deleteTaskFiles(sessionId);
      _tasks.remove(sessionId);
    }

    final list = _tasks.values.toList()
      ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

    if (!_listEquals(list, _notifier.value)) {
      _notifier.value = list;
    }
  }

  void _deleteTaskFiles(String sessionId) {
    try {
      final dir = _stateDirectory;
      final jsonFile = File('${dir.path}/vibe_task_$sessionId.json');
      if (jsonFile.existsSync()) {
        jsonFile.deleteSync();
      }
      final signalFile = File('${dir.path}/vibe_task_$sessionId.signal');
      if (signalFile.existsSync()) {
        signalFile.deleteSync();
      }
    } catch (error) {
      debugPrint('Failed to delete task files for $sessionId: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Periodic cleanup of stale files on disk
  // ---------------------------------------------------------------------------

  void _removeStaleFiles() {
    try {
      final dir = _stateDirectory;
      if (!dir.existsSync()) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final hardCutoff = DateTime.now().subtract(const Duration(hours: 1));

      for (final file in dir.listSync()) {
        if (file is! File) continue;
        final name = file.uri.pathSegments.last;

        // Clean stale .json files
        final jsonMatch = _fileNamePattern.firstMatch(name);
        if (jsonMatch != null) {
          final sessionId = jsonMatch.group(1)!;
          bool shouldDelete = false;

          // Hard cutoff: any file untouched for >1 hour is definitely orphaned.
          if (file.lastModifiedSync().isBefore(hardCutoff)) {
            shouldDelete = true;
          } else {
            // Try status-aware cleanup for files within the 1-hour window.
            try {
              final content = file.readAsStringSync();
              if (content.trim().isEmpty) {
                shouldDelete = true;
              } else {
                final json = jsonDecode(content) as Map<String, dynamic>;
                final ts = _asInt(json['timestamp']);
                if (ts != null) {
                  final age = now - ts;
                  if (age > _staleTaskMs) {
                    shouldDelete = true; // crashed / never finished
                  } else {
                    final status = VibeTaskStatus.fromString(
                        json['status'] as String? ?? 'idle');
                    switch (status) {
                      case VibeTaskStatus.completed:
                      case VibeTaskStatus.failed:
                      case VibeTaskStatus.stopped:
                        shouldDelete = age > _doneVisibilityMs;
                        break;
                      default:
                        break;
                    }
                  }
                }
              }
            } catch (_) {
              // If parsing fails, rely on the hard cutoff above.
            }
          }

          if (shouldDelete) {
            try {
              file.deleteSync();
              final signalFile =
                  File('${dir.path}/vibe_task_$sessionId.signal');
              if (signalFile.existsSync()) {
                signalFile.deleteSync();
              }
            } on FileSystemException {
              // File gone already.
            }
          }
          continue;
        }

        // Clean orphan .signal files (no corresponding .json)
        final signalMatch = _signalPattern.firstMatch(name);
        if (signalMatch != null) {
          final jsonFile =
              File('${dir.path}/vibe_task_${signalMatch.group(1)}.json');
          if (!jsonFile.existsSync()) {
            try {
              file.deleteSync();
            } on FileSystemException {
              // File gone already.
            }
          }
          continue;
        }
      }
    } catch (error) {
      debugPrint('Vibe task stale file cleanup error: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _ensureStateDirectory() {
    try {
      final dir = _stateDirectory;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (error) {
      debugPrint('Failed to create Vibe task state directory: $error');
    }
  }

  bool _listEquals(VibeTaskList a, VibeTaskList b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].sessionId != b[i].sessionId ||
          a[i].status != b[i].status ||
          a[i].timestamp != b[i].timestamp ||
          a[i].name != b[i].name) {
        return false;
      }
    }
    return true;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
