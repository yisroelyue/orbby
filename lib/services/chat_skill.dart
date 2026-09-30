import 'package:flutter/foundation.dart';

import 'palette_filter.dart';

/// 单条技能：输入 '@' 前缀触发的可引用能力。
/// 定义来自 ~/.orbby/skills/（目录式 SKILL.md 或散装单 md，解析见
/// SkillService）；技能正文与脚本资源由 Node 侧加载注入，Flutter 侧
/// 只承载面板展示所需的元数据。
class ChatSkill {
  const ChatSkill({required this.name, required this.description});

  /// 技能名（不含前导 '@'），同时也是输入过滤的关键词；不含空白
  final String name;

  /// 提示列表中展示的一句话说明
  final String description;
}

/// 技能面板状态：与 [CommandPaletteController] 同构的过滤与键盘导航，
/// 差异在触发语义——技能嵌在正文中引用（"帮我优化这段 @code-review"），
/// 只有 '@' 片段位于文本末尾（@ 之后无空白）时面板才可见；用户空格
/// 续写正文后面板自然收起，Enter 发送不会被劫持。
/// 纯逻辑、无 UI 依赖，展示层（SkillPalette）只读取
/// [visible] / [filtered] / [selectedIndex]。
class SkillPaletteController extends ChangeNotifier {
  SkillPaletteController({List<ChatSkill> skills = const []})
      : _skills = List.of(skills)..sort(_byName);

  static int _byName(ChatSkill a, ChatSkill b) => a.name.compareTo(b.name);

  final List<ChatSkill> _skills;
  final List<ChatSkill> _filtered = [];

  String _query = '';

  /// Esc 收起时的 query：文本不变则保持隐藏，一旦继续输入即恢复
  String? _dismissedAt;

  int _selectedIndex = 0;

  /// 运行时扩展点：注册新技能，自动按名称排序
  void register(ChatSkill skill) {
    _skills..add(skill)..sort(_byName);
    _refilter();
    notifyListeners();
  }

  /// 整表替换（启动加载与 /reload-skill 重扫共用）；
  /// 保持当前 query 重新过滤，正在输入的过滤态不被打断
  void replaceAll(List<ChatSkill> skills) {
    _skills
      ..clear()
      ..addAll(skills)
      ..sort(_byName);
    _refilter();
    notifyListeners();
  }

  /// 面板是否可见：末尾 '@' 片段非空、有匹配技能、且未被 Esc 收起
  bool get visible =>
      _query.startsWith('@') && _filtered.isNotEmpty && _dismissedAt != _query;

  /// 全部已注册技能（名称序）
  List<ChatSkill> get skills => List.unmodifiable(_skills);

  /// 当前过滤结果（按匹配优先级排序，同级保持名称序）
  List<ChatSkill> get filtered => List.unmodifiable(_filtered);

  /// 键盘选中项下标
  int get selectedIndex => _selectedIndex;

  /// 当前选中的技能；无匹配时为 null
  ChatSkill? get selected {
    if (_filtered.isEmpty) return null;
    final i = _selectedIndex.clamp(0, _filtered.length - 1);
    return _filtered[i];
  }

  /// 输入文本变化时调用：取最后一个 '@' 到文本末尾的片段过滤
  /// （不区分大小写）。片段含空白（引用已完成、在写正文）或无 '@'
  /// 时面板收起。
  void updateQuery(String text) {
    var query = '';
    final at = text.lastIndexOf('@');
    if (at >= 0) {
      final tail = text.substring(at);
      if (!tail.contains(RegExp(r'\s'))) query = tail;
    }
    if (query == _query) return;
    _query = query;
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

  /// 确认（Enter/Tab）：返回选中技能并收起面板；无选中时返回 null
  ChatSkill? confirm() {
    final skill = selected;
    if (skill == null) return null;
    _dismissedAt = _query;
    return skill;
  }

  /// Esc 收起面板
  void dismiss() {
    _dismissedAt = _query;
    notifyListeners();
  }

  /// 强制隐藏并清空 query（供宿主在 '/' 命令面板与 '@' 技能面板间
  /// 按最后触发字符互斥路由）；再次输入 '@' 时正常重新弹出
  void hide() {
    if (_query.isEmpty && _filtered.isEmpty) return;
    _query = '';
    _dismissedAt = null;
    _filtered.clear();
    _selectedIndex = 0;
    notifyListeners();
  }

  void _refilter() {
    final keyword =
        _query.length > 1 ? _query.substring(1).toLowerCase() : '';
    _filtered
      ..clear()
      ..addAll(
        _skills.where((s) => paletteMatches(s.name, keyword)),
      )
      ..sort((a, b) {
        final rank = paletteMatchRank(a.name, keyword).compareTo(
          paletteMatchRank(b.name, keyword),
        );
        return rank != 0 ? rank : _byName(a, b);
      });
    _selectedIndex = 0;
  }
}
