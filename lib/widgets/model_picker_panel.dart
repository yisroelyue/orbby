import 'package:flutter/material.dart';

import '../services/model_picker.dart';
import '../theme/chat_theme.dart';

/// 输入框右下角模型标签展开的切换浮层：配置 Chip 行 + 模型列表。
///
/// 纯展示组件（与 CommandPalette 同模式）：可见性、加载/错误态与键盘
/// 选中项均来自 [ModelPickerController]，本组件只负责渲染与点击；确认与
/// 收起动作经 [onConfirm] / [onDismiss]、切配置经 [onSwitchProfile]、
/// 新增配置经 [onAddProfile] 交回宿主处理（保存落盘、焦点归还都在宿主）。
/// 键盘 ↑/↓/Enter/Esc 由宿主在主输入框的按键接管层处理（同命令面板），
/// 本组件不含任何输入框。视觉与命令/技能面板同源（参考稿 .pop）：
/// raised 卡片 + 12px 圆角 + 浮层阴影。
class ModelPickerPanel extends StatefulWidget {
  const ModelPickerPanel({
    super.key,
    required this.controller,
    required this.onConfirm,
    required this.onDismiss,
    required this.onSwitchProfile,
    required this.onAddProfile,
  });

  final ModelPickerController controller;

  /// 确认选择（Enter / 点击列表项）
  final ValueChanged<String> onConfirm;

  /// 收起浮层（Esc / 点击面板外区域；焦点归还由宿主处理）
  final VoidCallback onDismiss;

  /// 切换激活配置（点 Chip；落盘由宿主处理）
  final ValueChanged<String> onSwitchProfile;

  /// 新增配置（＋Chip：关浮层并打开设置弹窗）
  final VoidCallback onAddProfile;

  @override
  State<ModelPickerPanel> createState() => _ModelPickerPanelState();
}

class _ModelPickerPanelState extends State<ModelPickerPanel> {
  /// 与聊天区统一（[ChatTheme.fontFamily]）
  static const _fontFamily = ChatTheme.fontFamily;

  static const _rowHeight = 34.0;
  static const _headerHeight = 32.0;
  static const _chipBarHeight = 38.0;
  static const _maxVisibleRows = 6;

  final _scrollController = ScrollController();
  int? _hoverIndex;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ModelPickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    // 键盘移动选中项时保证可见
    if (!widget.controller.visible || !_scrollController.hasClients) return;
    final target = (widget.controller.selectedIndex * _rowHeight).toDouble().clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if ((target - _scrollController.offset).abs() > 0.5) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.visible) return const SizedBox.shrink();

    final theme = ChatTheme.of(context);
    final rows = controller.models;
    return TapRegion(
      // 与输入区的模型标签同组：点击标签由标签自身 toggle 收起，
      // 点其他区域才走 onTapOutside
      groupId: controller.tapRegionGroup,
      onTapOutside: (_) => widget.onDismiss(),
      child: Container(
        // 不可见时是 shrink 的空盒，间距随浮层一起出现/消失
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          maxHeight: _chipBarHeight + _headerHeight + _rowHeight * _maxVisibleRows + 40,
        ),
        decoration: BoxDecoration(
          color: theme.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.line),
          boxShadow: theme.popShadows,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileChips(theme),
            _buildHeader(theme),
            if (controller.error != null) _buildError(theme),
            // 加载中只显示头部进度；错误态已有错误行，不再重复空态提示
            if (rows.isEmpty)
              (controller.loading || controller.error != null)
                  ? const SizedBox(height: 4)
                  : _buildEmptyHint(theme)
            else
              Flexible(
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemExtent: _rowHeight,
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  itemBuilder: (_, index) => _buildRow(
                    theme,
                    rows[index],
                    index,
                    index == controller.selectedIndex,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 配置 Chip 行：切换激活配置（横向滚动），行尾「＋」新增配置。
  /// 激活 Chip 走蓝色（infoSoft 底 + info 边），非激活沉底中性色
  Widget _buildProfileChips(ChatThemeData theme) {
    final controller = widget.controller;
    return SizedBox(
      height: _chipBarHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 10, left: 2, right: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final profile in controller.profiles)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _ProfileChip(
                  label: profile.name.trim().isEmpty
                      ? '未命名配置'
                      : profile.name.trim(),
                  active: profile.id == controller.activeProfileId,
                  onTap: () => widget.onSwitchProfile(profile.id),
                ),
              ),
            _ProfileChip(
              label: '新增配置',
              icon: Icons.add,
              active: false,
              onTap: widget.onAddProfile,
            ),
          ],
        ),
      ),
    );
  }

  /// 头部：标题（加载态文案）+ 刷新按钮
  Widget _buildHeader(ChatThemeData theme) {
    final controller = widget.controller;
    return SizedBox(
      height: _headerHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                controller.loading
                    ? '获取模型列表…'
                    : '模型（${controller.models.length}）',
                style: TextStyle(
                  color: theme.isDark ? Colors.white : theme.ink2,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  fontFamily: _fontFamily,
                ),
              ),
            ),
            if (controller.loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(theme.ink3),
                ),
              )
            else
              _RefreshIcon(onTap: controller.reload),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ChatThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Text(
        widget.controller.error!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.danger,
          fontSize: 12,
          fontFamily: _fontFamily,
        ),
      ),
    );
  }

  Widget _buildEmptyHint(ChatThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Text(
        '未获取到模型，可到设置中填写模型名',
        style: TextStyle(
          color: theme.ink3,
          fontSize: 12.5,
          fontFamily: _fontFamily,
        ),
      ),
    );
  }

  Widget _buildRow(
    ChatThemeData theme,
    String model,
    int index,
    bool selected,
  ) {
    final hovered = _hoverIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) => setState(() => _hoverIndex = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onConfirm(model),
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected || hovered
                ? (theme.isDark ? theme.hover : const Color(0xFFF3F4F6))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.isDark
                        ? Colors.white
                        : (selected ? theme.ink : theme.ink2),
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
              if (model == widget.controller.currentModel) ...[
                const SizedBox(width: 6),
                Icon(Icons.check, size: 15, color: theme.ok),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 头部的刷新按钮（重拉模型列表，跳过缓存）
class _RefreshIcon extends StatefulWidget {
  const _RefreshIcon({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RefreshIcon> createState() => _RefreshIconState();
}

class _RefreshIconState extends State<_RefreshIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            Icons.refresh,
            size: 15,
            color: _hovered ? theme.ink : theme.ink2,
          ),
        ),
      ),
    );
  }
}

/// 配置 Chip：激活 = infoSoft 蓝底 + info 描边 + ink 字（选中态刻意用
/// 蓝而非全局琥珀 accent——本浮层内的选中强调色）；
/// 非激活 = sunken 底 + lineSoft 描边，hover 提亮
class _ProfileChip extends StatefulWidget {
  const _ProfileChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<_ProfileChip> createState() => _ProfileChipState();
}

class _ProfileChipState extends State<_ProfileChip> {
  static const _fontFamily = ChatTheme.fontFamily;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    final fg = widget.active
        ? theme.ink
        : (_hovered ? theme.ink : theme.ink2);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: widget.active
                ? theme.infoSoft
                : (_hovered ? theme.raised : theme.sunken),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.active ? theme.info : theme.lineSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 13, color: fg),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
