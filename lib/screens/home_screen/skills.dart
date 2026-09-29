part of 'home_screen.dart';

/// '@' 技能：技能目录加载 + 面板确认。
/// 数据源 = SkillService 扫描 ~/.orbby/skills/（见 skill_service.dart）；
/// 新增技能 = 在该目录加一个 md 文件，无需改代码。
/// 当前仅做"选中后插入 @引用 继续编辑"，发送链路的技能生效后续接入。
extension _HomeScreenSkills on _HomeScreenState {
  /// 启动时扫描技能目录并注册进面板（异步；失败静默为空列表）
  Future<void> _loadSkills() async {
    final skills = await SkillService.loadSkills();
    if (!mounted) return;
    for (final skill in skills) {
      _skillPalette.register(skill);
    }
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
