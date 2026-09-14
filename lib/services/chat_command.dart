import 'package:flutter/foundation.dart';

/// 命令确认后的行为：
/// - immediate：立即执行（现有全部命令）
/// - prepareInput：不执行动作，只把 `/命令名 ` 写入输入框，
///   让用户补充内容后再发送（如 /image-analyze 后补图片与说明）
enum ChatCommandBehavior { immediate, prepareInput }

/// 单条聊天命令：输入 '/' 前缀触发的快捷指令。
/// 新增命令只需向 [CommandPaletteController] 注册一个实例，不涉及 UI 改动。
class ChatCommand {
  const ChatCommand({
    required this.name,
    required this.description,
    required this.execute,
    this.behavior = ChatCommandBehavior.immediate,
  });

  /// 命令名（不含前导 '/'），同时也是输入过滤的关键词
  final String name;

  /// 提示列表中展示的一句话说明
  final String description;

  /// 命令被确认（Enter/Tab/点击）后执行
  final VoidCallback execute;

  /// 确认后的行为（见 [ChatCommandBehavior]）
  final ChatCommandBehavior behavior;
}

/// 命令面板状态：持有命令注册表，按输入 query 过滤并维护键盘选中项。
/// 纯逻辑、无 UI 依赖，展示层（CommandPalette）只读取
/// [visible] / [filtered] / [selectedIndex]。
class CommandPaletteController extends ChangeNotifier {
  CommandPaletteController({List<ChatCommand> commands = const []})
      : _commands = List.of(commands)..sort(_byName);

  static int _byName(ChatCommand a, ChatCommand b) => a.name.compareTo(b.name);

  final List<ChatCommand> _commands;
  final List<ChatCommand> _filtered = [];

  String _query = '';

  /// Esc 收起时的 query：文本不变则保持隐藏，一旦继续输入即恢复
  String? _dismissedAt;

  int _selectedIndex = 0;

  /// 运行时扩展点：注册新命令，自动按名称排序
  void register(ChatCommand command) {
    _commands..add(command)..sort(_byName);
    _refilter();
    notifyListeners();
  }

  /// 面板是否可见：输入以 '/' 开头、有匹配命令、且未被 Esc 收起
  bool get visible =>
      _query.startsWith('/') && _filtered.isNotEmpty && _dismissedAt != _query;

  /// 全部已注册命令（名称序），如 /help 列举用
  List<ChatCommand> get commands => List.unmodifiable(_commands);

  /// 当前过滤结果（保持名称序）
  List<ChatCommand> get filtered => List.unmodifiable(_filtered);

  /// 键盘选中项下标
  int get selectedIndex => _selectedIndex;

  /// 当前选中的命令；无匹配时为 null
  ChatCommand? get selected {
    if (_filtered.isEmpty) return null;
    final i = _selectedIndex.clamp(0, _filtered.length - 1);
    return _filtered[i];
  }

  /// 按名称精确查找（不含前导 '/'，不区分大小写）
  ChatCommand? findExact(String name) {
    final n = name.toLowerCase();
    for (final c in _commands) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  /// 输入文本变化时调用：支持命令名前缀和分隔词首字母缩写（不区分大小写）。
  /// 例如输入 `/cs` 可匹配 `/clear-session`。
  void updateQuery(String text) {
    if (text == _query) return;
    _query = text;
    _dismissedAt = null;
    _refilter();
    notifyListeners();
  }

  void movePrevious() => _move(-1);

  void moveNext() => _move(1);

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    _selectedIndex = (_selectedIndex + delta) % _filtered.length;
    notifyListeners();
  }

  /// 确认（Enter/Tab）：返回选中命令并收起面板；无选中时返回 null
  ChatCommand? confirm() {
    final cmd = selected;
    if (cmd == null) return null;
    _dismissedAt = _query;
    return cmd;
  }

  /// Esc 收起面板
  void dismiss() {
    _dismissedAt = _query;
    notifyListeners();
  }

  void _refilter() {
    final keyword =
        _query.length > 1 ? _query.substring(1).toLowerCase() : '';
    _filtered
      ..clear()
      ..addAll(
        _commands.where((c) => _matches(c.name, keyword)),
      );
    _selectedIndex = 0;
  }

  bool _matches(String name, String keyword) {
    if (keyword.isEmpty) return true;
    final normalized = name.toLowerCase();
    if (normalized.startsWith(keyword)) return true;

    final initials = normalized
        .split(RegExp(r'[-_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .join();
    return initials.startsWith(keyword);
  }
}
