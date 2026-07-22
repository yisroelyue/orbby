import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class ClaudeHookInstallResult {
  const ClaudeHookInstallResult({
    required this.hookPath,
    required this.settingsPath,
  });

  final String hookPath;
  final String settingsPath;
}

class ClaudeHookInstaller {
  ClaudeHookInstaller._();

  static const _assetPath = 'assets/scripts/vibe_task_update.ps1';
  static const _events = [
    'SessionStart',
    'UserPromptSubmit',
    'PreToolUse',
    'PostToolUse',
    'Notification',
    'Stop',
    'SubagentStop',
  ];

  static Future<ClaudeHookInstallResult> installGlobalHooks() async {
    final paths = _resolvePaths();
    await paths.hookFile.parent.create(recursive: true);
    await paths.settingsFile.parent.create(recursive: true);

    final script = await rootBundle.loadString(_assetPath);
    await paths.hookFile.writeAsString(script, encoding: utf8);

    final settings = await _loadSettings(paths.settingsFile);
    final hooks = _asMap(settings['hooks']) ?? <String, dynamic>{};
    settings['hooks'] = hooks;

    final command = _hookCommand(paths.hookFile);
    for (final event in _events) {
      final entries = _removeOrbbyHookCommands(
        _asList(hooks[event]),
        keepCommand: command,
      );
      if (!_containsCommand(entries, command)) {
        entries.add({
          'matcher': '',
          'hooks': [
            {
              'type': 'command',
              'command': command,
            },
          ],
        });
      }
      hooks[event] = entries;
    }

    await paths.settingsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
      encoding: utf8,
    );

    return ClaudeHookInstallResult(
      hookPath: paths.hookFile.path,
      settingsPath: paths.settingsFile.path,
    );
  }

  static Future<bool> isGlobalHookInstalled() async {
    final paths = _resolvePaths();
    if (!await paths.hookFile.exists() || !await paths.settingsFile.exists()) {
      return false;
    }

    final settings = await _loadSettings(paths.settingsFile);
    final hooks = _asMap(settings['hooks']);
    if (hooks == null) return false;

    final command = _hookCommand(paths.hookFile);
    return _events.every((event) {
      return _containsCommand(_asList(hooks[event]), command);
    });
  }

  static Future<Map<String, dynamic>> _loadSettings(File file) async {
    try {
      if (!await file.exists()) return <String, dynamic>{};
      final content = await file.readAsString(encoding: utf8);
      if (content.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static _ClaudeHookPaths _resolvePaths() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final orbbyDir = Directory('$home\\.orbby\\claude_task');
    final claudeDir = Directory('$home\\.claude');

    return _ClaudeHookPaths(
      hookFile: File('${orbbyDir.path}\\hooks\\vibe_task_update.ps1'),
      settingsFile: File('${claudeDir.path}\\settings.json'),
    );
  }

  static String _hookCommand(File hookFile) {
    final path = hookFile.absolute.path.replaceAll('\\', '/');
    return 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$path"';
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) return List<dynamic>.from(value);
    if (value == null) return <dynamic>[];
    return <dynamic>[value];
  }

  static bool _containsCommand(List<dynamic> entries, String command) {
    for (final entry in entries) {
      final entryMap = _asMap(entry);
      final hooks = _asList(entryMap?['hooks']);
      for (final hook in hooks) {
        final hookMap = _asMap(hook);
        if (hookMap?['command'] == command) {
          return true;
        }
      }
    }
    return false;
  }

  static List<dynamic> _removeOrbbyHookCommands(
    List<dynamic> entries, {
    required String keepCommand,
  }) {
    final cleanedEntries = <dynamic>[];

    for (final entry in entries) {
      final entryMap = _asMap(entry);
      if (entryMap == null) {
        cleanedEntries.add(entry);
        continue;
      }

      final hooks = _asList(entryMap['hooks']);
      final cleanedHooks = <dynamic>[];
      for (final hook in hooks) {
        final hookMap = _asMap(hook);
        final command = hookMap?['command'] as String?;
        if (command != null &&
            command != keepCommand &&
            _isOrbbyHookCommand(command)) {
          continue;
        }
        cleanedHooks.add(hook);
      }

      if (cleanedHooks.isEmpty) {
        continue;
      }

      final cleanedEntry = Map<String, dynamic>.from(entryMap);
      cleanedEntry['hooks'] = cleanedHooks;
      cleanedEntries.add(cleanedEntry);
    }

    return cleanedEntries;
  }

  static bool _isOrbbyHookCommand(String command) {
    final normalized = command.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('vibe_task_update.ps1') &&
        (normalized.contains('/.orbby/hooks/') ||
            normalized.contains('/orbby/.claude/hooks/'));
  }
}

class _ClaudeHookPaths {
  const _ClaudeHookPaths({
    required this.hookFile,
    required this.settingsFile,
  });

  final File hookFile;
  final File settingsFile;
}
