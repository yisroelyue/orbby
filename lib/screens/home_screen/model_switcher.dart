part of 'home_screen.dart';

/// 输入框右下角模型标签的切换浮层：配置 Chip 行（切激活配置）+ 模型列表。
/// 切配置 / 切模型都即时落盘并广播 settingsChanged，在下一次发送时经
/// chat.start 的 llm 快照生效（进行中的请求不受影响，无需禁用切换）。
extension _HomeScreenModelSwitcher on _HomeScreenState {
  /// 模型标签点击：浮层已展开则收起，否则读取设置展开并拉取模型列表
  Future<void> _toggleModelPicker() async {
    if (_modelPicker.visible) {
      _closeModelPicker();
      return;
    }
    // 浮层自带过滤输入框并接管键盘，与命令/技能面板互斥收起
    _palette.hide();
    _skillPalette.hide();
    final settings = await SettingsService.load();
    if (!mounted || _modelPicker.visible) return;
    await _modelPicker.open(
      profiles: settings.profiles,
      activeProfileId: settings.activeProfileId,
    );
  }

  /// 收起浮层并把焦点归还主输入框（Esc / 点击外部 / 确认后共用）
  void _closeModelPicker() {
    _modelPicker.close();
    _inputFocus.requestFocus();
  }

  /// 切换激活配置（点 Chip）：controller 先切（浮层立即重拉新配置的
  /// 模型列表），宿主随后落盘 + 刷新模型标签
  Future<void> _switchApiProfile(String id) async {
    await _modelPicker.switchProfile(id);
    final settings = await SettingsService.load();
    // id 来自浮层打开时的快照，理论上必在最新列表内；防御弹窗等
    // 并发改动导致悬空（悬空时 normalize 会拉回首条，落盘必失真）
    if (settings.profiles.any((p) => p.id == id)) {
      settings.activeProfileId = id;
    }
    await SettingsService.save(settings);
    AppEvents.emit(AppEvents.settingsChanged);
    if (!mounted) return;
    setState(() => _modelLabel = _modelLabelText(settings.activeProfile));
  }

  /// 确认选择模型：写回激活配置的 model 并落盘（与设置弹窗保存同语义），
  /// 刷新模型标签并 toast 反馈
  Future<void> _confirmModelSelection(String model) async {
    if (model.isEmpty) return;
    _modelPicker.close();
    _inputFocus.requestFocus();
    final settings = await SettingsService.load();
    settings.activeProfile.model = model;
    await SettingsService.save(settings);
    AppEvents.emit(AppEvents.settingsChanged);
    if (!mounted) return;
    setState(() => _modelLabel = model);
    AppToast.show(context, message: '已切换模型：$model');
  }

  /// 浮层「＋」Chip：关浮层并打开设置弹窗（新增/编辑配置在弹窗里做）
  void _addApiProfileFromPicker() {
    _closeModelPicker();
    _showAgentSettings();
  }

  /// 模型标签文案：model 空 → 引导文案
  String _modelLabelText(ApiProfile profile) =>
      profile.model.trim().isEmpty ? '未设置模型' : profile.model.trim();
}
