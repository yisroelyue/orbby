part of 'home_screen.dart';

/// '@' 技能：技能目录加载 + 面板确认。
/// 数据源 = SkillService 扫描 ~/.orbby/skills/（见 skill_service.dart）；
/// 新增技能 = 在该目录加一个 md 文件，无需改代码。
/// 当前仅做"选中后插入 @引用 继续编辑"，发送链路的技能生效后续接入。
extension _HomeScreenSkills on _HomeScreenState {
  /// 扫描技能目录并整表注册进面板；返回技能数量
  /// （启动加载、/reload-skill 命令与 skills.changed 推送共用）
  Future<int> _loadSkills() async {
    final skills = await SkillService.loadSkills();
    if (mounted) _skillPalette.replaceAll(skills);
    return skills.length;
  }

  /// 订阅 Node 侧技能目录监听推送：技能目录任何文件变化（LLM 创建技能、
  /// 用户手改）都会触发广播 skills.changed，这里静默重扫面板——创建/修改
  /// 技能后立即可 @ 引用，无需手动 /reload-skill（该命令保留为兜底）
  void _subscribeSkillChanges() {
    _skillsChangedSub = AgentService.serverEvents
        .where((e) => e['type'] == 'skills.changed')
        .listen((_) => _loadSkills(), onError: (Object e, StackTrace s) {});
  }

  /// /reload-skill：重扫技能目录并清 Node 侧缓存（下次引用展开时重扫），
  /// 加/改技能文件后无需重启应用；Node 未连接时仅面板生效
  Future<void> _reloadSkillsCommand() async {
    final count = await _loadSkills();
    try {
      await AgentService.reloadSkills();
    } catch (_) {
      // runtime 未连接：面板已更新，不打断命令
    }
    if (!mounted) return;
    _addLocalMessage('已重新扫描技能目录：$count 个技能');
  }

  /// 确认（Enter/Tab/点击）技能：把文本末尾的 '@ 片段' 替换为
  /// '@技能名 '，保留前后正文继续编辑；不清空输入框、不执行动作。
  /// 确认后面板随 updateQuery 自然收起（新文本尾随空格 = 引用完成）。
  void _confirmSkill([ChatSkill? skill]) {
    skill ??= _skillPalette.confirm();
    if (skill == null) return;
    final text = _inputController.text;
    final at = text.lastIndexOf('@');
    if (at < 0) return;
    final next = text.replaceRange(at, text.length, '@${skill.name} ');
    _inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocus.requestFocus();
  }
}
