import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// 剪贴板历史管理服务
/// 由原生层 WM_CLIPBOARDUPDATE 事件驱动，无需轮询
/// 历史记录持久化到 ~/.orbby/clipboard_history.json，供跨窗口进程共享
class ClipboardService {
  ClipboardService._();
  static final ClipboardService instance = ClipboardService._();

  static const _maxHistory = 10;

  final List<String> _history = [];
  String _lastClipboardContent = '';
  bool _isRunning = false;

  /// 历史记录变更回调
  void Function(List<String>)? onHistoryChanged;

  List<String> get history => List.unmodifiable(_history);
  bool get isRunning => _isRunning;

  /// 获取持久化文件路径
  static Future<File> _historyFile() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/clipboard_history.json');
  }

  /// 从文件加载历史记录（供弹窗进程使用）
  static Future<List<String>> loadHistory() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString());
      if (json is List) {
        return json.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 持久化历史记录到文件
  Future<void> _saveHistory() async {
    try {
      final file = await _historyFile();
      await file.writeAsString(jsonEncode(_history));
    } catch (_) {}
  }

  /// 开始监听（从文件恢复历史，初始化剪贴板快照）
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    // 启动时从文件恢复历史
    final saved = await loadHistory();
    _history.clear();
    _history.addAll(saved);

    // 记录当前剪贴板内容，避免把已有内容当成"新复制"
    _lastClipboardContent = await _readClipboard();
  }

  /// 停止监听
  void stop() {
    _isRunning = false;
  }

  /// 由原生层 WM_CLIPBOARDUPDATE 事件调用
  Future<void> onClipboardChanged() async {
    if (!_isRunning) return;
    try {
      final content = await _readClipboard();
      if (content.isNotEmpty && content != _lastClipboardContent) {
        _lastClipboardContent = content;
        _addToHistory(content);
      }
    } catch (_) {}
  }

  /// 读取系统剪贴板
  Future<String> _readClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text ?? '';
  }

  /// 添加内容到历史记录
  void _addToHistory(String content) {
    _history.remove(content);
    _history.insert(0, content);

    while (_history.length > _maxHistory) {
      _history.removeLast();
    }

    _saveHistory();
    onHistoryChanged?.call(history);
  }

  /// 选择某条历史记录并复制到剪贴板
  Future<void> selectItem(int index) async {
    if (index < 0 || index >= _history.length) return;
    final content = _history[index];
    await Clipboard.setData(ClipboardData(text: content));
    _lastClipboardContent = content;

    _history.removeAt(index);
    _history.insert(0, content);
    _saveHistory();
    onHistoryChanged?.call(history);
  }

  /// 清空历史
  void clear() {
    _history.clear();
    _saveHistory();
    onHistoryChanged?.call(history);
  }

  void dispose() {
    stop();
  }
}
