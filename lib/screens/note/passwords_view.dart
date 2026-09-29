import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/password_service.dart';
import 'note_theme.dart';

enum _PwPhase { setup, setupConfirm, locked, unlocked }

/// 密码本视图：锁定（PIN）/ 首次设置 / 已解锁三态。
/// - 列表沿用笔记的折叠单行 / 点击展开模型，同时仅一条展开；
/// - 掩码默认，行内眼睛临时明文（等宽字体），展开态默认明文；
/// - 连续输错 3 次冷却 30 秒；锁定/切走时清空全部明文与编辑状态。
/// 状态经 onStatus 回调给外壳（头部副标题、底部按钮、闲置计时）。
class PasswordsView extends StatefulWidget {
  const PasswordsView({super.key, required this.onStatus});

  /// locked：是否处于锁定（含未设置主密码）；count：锁定态取库文件头
  /// 计数、解锁态取内存条目数；hasVault：是否已设置主密码。
  final void Function(bool locked, int count, bool hasVault) onStatus;

  @override
  State<PasswordsView> createState() => PasswordsViewState();
}

class PasswordsViewState extends State<PasswordsView> {
  _PwPhase _phase = _PwPhase.locked;
  bool _hasVault = false;
  int _count = 0;
  bool _loading = true;

  final _pinCtrl = TextEditingController();
  final _pinFocus = FocusNode();
  bool _blinkOn = true;
  Timer? _blinkTimer;

  String? _alert;
  int _failCount = 0;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  String? _setupPin;

  List<PasswordEntry> _entries = const [];
  String? _expandedId;
  bool _expandedRevealed = true;
  final _revealedIds = <String>{};

  String? _editingId; // null | 'new' | 条目 id
  final _titleCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _titleFocus = FocusNode();
  String _formKind = 'key';
  bool _formPwVisible = true;

  static const _kinds = {'key': '账号密码', 'card': '银行卡', 'server': '服务器 / 网络', 'doc': '证件 / 资料'};

  @override
  void initState() {
    super.initState();
    _pinCtrl.addListener(_onPinChanged);
    _init();
  }

  @override
  void dispose() {
    _pinCtrl.removeListener(_onPinChanged);
    _pinCtrl.dispose();
    _pinFocus.dispose();
    _titleCtrl.dispose();
    _userCtrl.dispose();
    _pwCtrl.dispose();
    _titleFocus.dispose();
    _blinkTimer?.cancel();
    _cooldownTimer?.cancel();
    PasswordVault.lock();
    super.dispose();
  }

  void _onPinChanged() {
    if (_phase != _PwPhase.unlocked) setState(() {});
  }

  Future<void> _init() async {
    _hasVault = await PasswordVault.hasVault();
    _count = await PasswordVault.entryCount();
    _setPhase(_hasVault ? _PwPhase.locked : _PwPhase.setup);
    _loading = false;
    _notifyStatus();
    if (mounted) setState(() {});
  }

  void _notifyStatus() {
    widget.onStatus(
      _phase != _PwPhase.unlocked,
      _phase == _PwPhase.unlocked ? _entries.length : _count,
      _hasVault,
    );
  }

  void _setPhase(_PwPhase phase) {
    _phase = phase;
    _blinkTimer?.cancel();
    _blinkTimer = null;
    if (phase != _PwPhase.unlocked) {
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 550), (_) {
        if (!mounted) return;
        setState(() => _blinkOn = !_blinkOn);
      });
    }
  }

  void _focusPin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phase != _PwPhase.unlocked) _pinFocus.requestFocus();
    });
  }

  void _focusTitle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingId != null) _titleFocus.requestFocus();
    });
  }

  /// 外壳切换到密码本视图时调用：聚焦 PIN 输入。
  void onShown() => _focusPin();

  /// 外壳切回笔记视图 / 闲置超时时调用：立即锁定并复位全部状态。
  void lockNow() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _cooldown = 0;
    _failCount = 0;
    _alert = null;
    _setupPin = null;
    _pinCtrl.clear();
    _pinFocus.unfocus();
    _exitForm();
    _expandedId = null;
    _expandedRevealed = true;
    _revealedIds.clear();
    PasswordVault.lock();
    _entries = const [];
    _setPhase(_hasVault ? _PwPhase.locked : _PwPhase.setup);
    _notifyStatus();
    if (mounted) setState(() {});
  }

  /// 外壳底部「新建密码」入口。
  void startCreate() {
    if (_phase != _PwPhase.unlocked) return;
    _exitForm();
    _expandedId = null;
    _editingId = 'new';
    _titleCtrl.clear();
    _userCtrl.clear();
    _pwCtrl.clear();
    _formKind = 'key';
    _formPwVisible = true;
    setState(() {});
    _focusTitle();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldown = 30;
    setState(() => _alert = '连续输错 3 次，请稍候再试');
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _cooldown--;
      if (_cooldown <= 0) {
        timer.cancel();
        _cooldownTimer = null;
        _failCount = 0;
        setState(() => _alert = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submitPin() async {
    final pin = _pinCtrl.text;
    if (pin.length != 6 || _cooldown > 0) return;
    switch (_phase) {
      case _PwPhase.setup:
        _setupPin = pin;
        _pinCtrl.clear();
        setState(() => _alert = null);
        _setPhase(_PwPhase.setupConfirm);
        _focusPin();
      case _PwPhase.setupConfirm:
        if (pin == _setupPin) {
          _setupPin = null;
          _pinCtrl.clear();
          _pinFocus.unfocus();
          await PasswordVault.setup(pin);
          _hasVault = true;
          _entries = PasswordVault.entries;
          _setPhase(_PwPhase.unlocked);
          _notifyStatus();
          setState(() {});
        } else {
          _setupPin = null;
          _pinCtrl.clear();
          setState(() => _alert = '两次输入不一致，请重新设置');
          _setPhase(_PwPhase.setup);
          _focusPin();
        }
      case _PwPhase.locked:
        final ok = await PasswordVault.unlock(pin);
        if (!mounted) return;
        if (ok) {
          _pinCtrl.clear();
          _pinFocus.unfocus();
          _failCount = 0;
          _alert = null;
          _entries = PasswordVault.entries;
          _setPhase(_PwPhase.unlocked);
          _notifyStatus();
          setState(() {});
        } else {
          _pinCtrl.clear();
          _failCount++;
          if (_failCount >= 3) {
            _startCooldown();
          } else {
            setState(() => _alert = '主密码不正确，请重试');
          }
          _focusPin();
        }
      case _PwPhase.unlocked:
        break;
    }
  }

  void _expand(PasswordEntry entry) {
    _exitForm();
    setState(() {
      _expandedId = _expandedId == entry.id ? null : entry.id;
      _expandedRevealed = true;
    });
  }

  void _exitForm() {
    _editingId = null;
  }

  void _startEdit(PasswordEntry entry) {
    _exitForm();
    _expandedId = null;
    _editingId = entry.id;
    _titleCtrl.text = entry.title;
    _userCtrl.text = entry.username;
    _pwCtrl.text = entry.password;
    _formKind = _kinds.containsKey(entry.kind) ? entry.kind : 'key';
    _formPwVisible = true;
    setState(() {});
    _focusTitle();
  }

  Future<void> _saveForm() async {
    final id = _editingId;
    if (id == null) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('请填写名称');
      return;
    }
    final username = _userCtrl.text.trim();
    final password = _pwCtrl.text;
    if (id == 'new') {
      await PasswordVault.add(
        title: title,
        username: username,
        password: password,
        kind: _formKind,
      );
    } else {
      PasswordEntry? old;
      for (final e in _entries) {
        if (e.id == id) old = e;
      }
      if (old == null) return;
      await PasswordVault.update(PasswordEntry(
        id: id,
        title: title,
        username: username,
        password: password,
        kind: _formKind,
        createdAt: old.createdAt,
      ));
    }
    _refreshEntries();
    _exitForm();
    setState(() {});
  }

  Future<void> _deleteEntry(PasswordEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(message: '「${entry.title}」将被删除，无法恢复。'),
    );
    if (ok != true || !mounted) return;
    await PasswordVault.remove(entry.id);
    if (_expandedId == entry.id) {
      _expandedId = null;
      _expandedRevealed = true;
    }
    _refreshEntries();
    setState(() {});
  }

  void _refreshEntries() {
    _entries = List.of(PasswordVault.entries);
    _notifyStatus();
  }

  void _copy(String value, String label) {
    if (value.isEmpty) {
      _toast('未设置$label');
      return;
    }
    Clipboard.setData(ClipboardData(text: value));
    _toast('已复制$label');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 12, color: NoteColors.ink),
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
        duration: const Duration(milliseconds: 1600),
        margin: const EdgeInsets.only(bottom: 14),
        width: 200,
      ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: NoteColors.ink3),
      );
    }
    if (_phase == _PwPhase.unlocked) return _buildList();
    return _buildPinPanel();
  }

  // ---------------- 锁定 / 设置面板 ----------------

  Widget _buildPinPanel() {
    final pin = _pinCtrl.text;
    final String title;
    final String sub;
    final bool lockedMode = _phase == _PwPhase.locked;
    if (lockedMode) {
      title = '密码本已锁定';
      sub = _count > 0 ? '输入 6 位主密码，查看 $_count 个密码' : '输入 6 位主密码';
    } else if (_phase == _PwPhase.setup) {
      title = '设置主密码';
      sub = '输入 6 位主密码，之后用于解锁密码本';
    } else {
      title = '设置主密码';
      sub = '请再次输入以确认';
    }
    final buttonLabel = _cooldown > 0
        ? '请 $_cooldown 秒后重试'
        : (lockedMode ? '解锁' : '设置主密码');
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LockMark(),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: NoteColors.ink),
            ),
            const SizedBox(height: 7),
            Text(sub, style: const TextStyle(fontSize: 12, color: NoteColors.ink3, letterSpacing: .1)),
            if (_alert != null) ...[
              const SizedBox(height: 16),
              _AlertBar(message: _alert!),
            ],
            const SizedBox(height: 24),
            _buildPins(pin),
            const SizedBox(height: 22),
            PrimaryButton(
              label: buttonLabel,
              width: 240,
              icon: Icons.lock_open_outlined,
              onTap: (pin.length == 6 && _cooldown == 0) ? _submitPin : null,
            ),
            const SizedBox(height: 18),
            Text(
              lockedMode ? '离开密码本后自动重新锁定\n主密码仅保存在本机，忘记后无法恢复' : '主密码仅保存在本机，忘记后无法恢复',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: NoteColors.ink3, height: 1.7, letterSpacing: .2),
            ),
            // 隐藏输入框承载 PIN 键盘输入（点击格子聚焦）
            SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                controller: _pinCtrl,
                focusNode: _pinFocus,
                showCursor: false,
                autofocus: false,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(fontSize: 1),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPins(String pin) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pinFocus.requestFocus,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            _pinBox(i, pin),
          ],
        ],
      ),
    );
  }

  Widget _pinBox(int index, String pin) {
    final filled = index < pin.length;
    final current = index == pin.length && pin.length < 6;
    return Container(
      width: 46,
      height: 54,
      decoration: BoxDecoration(
        color: NoteColors.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: current ? NoteColors.accent : NoteColors.line,
          width: current ? 1.5 : 1,
        ),
        boxShadow: [
          const BoxShadow(color: Color(0x0A1F2A44), blurRadius: 2, offset: Offset(0, 1)),
          if (current) const BoxShadow(color: Color(0x38FFC145), blurRadius: 0, spreadRadius: 3),
        ],
      ),
      child: Center(
        child: filled
            ? Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(color: NoteColors.ink, shape: BoxShape.circle),
              )
            : (current
                ? AnimatedOpacity(
                    opacity: _blinkOn ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: Container(width: 2, height: 20, color: NoteColors.accent),
                  )
                : null),
      ),
    );
  }

  // ---------------- 解锁列表 ----------------

  Widget _buildList() {
    final children = <Widget>[
      if (_editingId == 'new')
        _buildFormCard(),
      for (final entry in _entries)
        if (_editingId == entry.id)
          _buildFormCard(entry: entry)
        else if (_expandedId == entry.id)
          _buildDetailCard(entry)
        else
          _buildRow(entry),
    ];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: children.length,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
        child: children[index],
      ),
    );
  }

  Widget _kindIcon(String kind, {double size = 24}) => SvgPicture.asset(
        'assets/svg/$kind.svg',
        width: size,
        height: size,
      );

  Widget _maskOrPlain(PasswordEntry entry, bool revealed) {
    if (entry.password.isEmpty) {
      return const Text('—', style: TextStyle(fontSize: 12.5, color: NoteColors.ink3));
    }
    if (revealed) {
      return Text(
        entry.password,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 12.5,
          color: NoteColors.ink,
          letterSpacing: .5,
        ),
      );
    }
    return Text(
      '•' * entry.password.length.clamp(1, 12),
      style: const TextStyle(fontSize: 13, color: NoteColors.ink2, letterSpacing: 1.5),
    );
  }

  Widget _buildRow(PasswordEntry entry) {
    final revealed = _revealedIds.contains(entry.id);
    return HoverBuilder(
      builder: (context, hover) => GestureDetector(
        onTap: () => _expand(entry),
        child: Container(
          height: 54,
          padding: const EdgeInsets.only(left: 14, right: 10),
          decoration: noteCardDecoration(hover: hover),
          child: Row(
            children: [
              _kindIcon(entry.kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.isEmpty ? '未命名' : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        letterSpacing: .1,
                        color: NoteColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.username.isEmpty ? '—' : entry.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, height: 1.25, color: NoteColors.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _maskOrPlain(entry, revealed)),
              const SizedBox(width: 6),
              IconAction(
                icon: Icons.visibility_outlined,
                tooltip: revealed ? '隐藏密码' : '显示密码',
                color: NoteColors.ink3,
                active: revealed,
                small: true,
                onTap: () => setState(() {
                  if (revealed) {
                    _revealedIds.remove(entry.id);
                  } else {
                    _revealedIds.add(entry.id);
                  }
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard(PasswordEntry entry) {
    final rows = <Widget>[
      _fieldRow(label: '名称', child: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _valueStyle)),
      _fieldRow(
        label: '账号',
        child: Text(entry.username.isEmpty ? '—' : entry.username,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: _valueStyle),
        trailing: IconAction(
          icon: Icons.content_copy_outlined,
          tooltip: '复制账号',
          small: true,
          onTap: () => _copy(entry.username, '账号'),
        ),
      ),
      _fieldRow(
        label: '密码',
        child: _maskOrPlain(entry, _expandedRevealed),
        trailing: IconAction(
          icon: Icons.visibility_outlined,
          tooltip: _expandedRevealed ? '隐藏密码' : '显示密码',
          active: _expandedRevealed,
          small: true,
          onTap: () => setState(() => _expandedRevealed = !_expandedRevealed),
        ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: noteEditorDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kindIcon(entry.kind),
          const SizedBox(height: 9),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: NoteColors.lineSoft),
            rows[i],
          ],
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.only(top: 10, right: 3, left: 3),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: NoteColors.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextAction(
                  label: '复制密码',
                  icon: Icons.content_copy_outlined,
                  onTap: () => _copy(entry.password, '密码'),
                ),
                const SizedBox(width: 6),
                TextAction(
                  label: '编辑',
                  icon: Icons.edit_outlined,
                  onTap: () => _startEdit(entry),
                ),
                const SizedBox(width: 6),
                TextAction(
                  label: '删除',
                  icon: Icons.delete_outline_rounded,
                  danger: true,
                  onTap: () => _deleteEntry(entry),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _valueStyle = TextStyle(fontSize: 13, color: NoteColors.body, letterSpacing: .1);

  Widget _fieldRow({required String label, required Widget child, Widget? trailing}) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: NoteColors.ink3, letterSpacing: .2)),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing,
          ],
        ],
      ),
    );
  }

  // ---------------- 新建 / 编辑表单 ----------------

  Widget _buildFormCard({PasswordEntry? entry}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: noteEditorDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kindIcon(_formKind),
          const SizedBox(height: 9),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: NoteColors.line)),
            ),
            child: Column(
              children: [
                _formKindRow(),
                const Divider(height: 1, thickness: 1, color: NoteColors.lineSoft),
                _formFieldRow(
                  label: '名称',
                  child: TextField(
                    controller: _titleCtrl,
                    focusNode: _titleFocus,
                    style: _valueStyle,
                    decoration: _formInputDecoration('名称'),
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: NoteColors.lineSoft),
                _formFieldRow(
                  label: '账号',
                  child: TextField(
                    controller: _userCtrl,
                    style: _valueStyle,
                    decoration: _formInputDecoration('账号 / 用户名'),
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: NoteColors.lineSoft),
                _formFieldRow(
                  label: '密码',
                  child: TextField(
                    controller: _pwCtrl,
                    obscureText: !_formPwVisible,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12.5,
                      color: NoteColors.ink,
                      letterSpacing: .5,
                    ),
                    decoration: _formInputDecoration('密码').copyWith(
                      isDense: false,
                      suffixIcon: IconAction(
                        icon: Icons.visibility_outlined,
                        tooltip: _formPwVisible ? '隐藏密码' : '显示密码',
                        active: _formPwVisible,
                        small: true,
                        onTap: () => setState(() => _formPwVisible = !_formPwVisible),
                      ),
                      suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.only(top: 10, right: 3),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: NoteColors.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextAction(
                  label: entry == null ? '创建' : '保存',
                  icon: Icons.check_rounded,
                  onTap: _saveForm,
                ),
                const SizedBox(width: 6),
                TextAction(
                  label: '取消',
                  icon: Icons.close_rounded,
                  onTap: () => setState(_exitForm),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _formInputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12.5, color: NoteColors.ink3),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
      );

  Widget _formKindRow() {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: const Text('类别', style: TextStyle(fontSize: 11.5, color: NoteColors.ink3, letterSpacing: .2)),
          ),
          const SizedBox(width: 12),
          for (final kind in _kinds.keys) ...[
            if (kind != _kinds.keys.first) const SizedBox(width: 8),
            Tooltip(
              message: _kinds[kind]!,
              child: GestureDetector(
                onTap: () => setState(() => _formKind = kind),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _formKind == kind ? NoteColors.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _formKind == kind ? NoteColors.accent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Center(child: _kindIcon(kind, size: 18)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formFieldRow({required String label, required Widget child}) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: NoteColors.ink3, letterSpacing: .2)),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 锁定态锁标：墨底圆角方块 + 白锁梁 + 琥珀锁体。
class _LockMark extends StatelessWidget {
  const _LockMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: NoteColors.ink,
        borderRadius: BorderRadius.circular(17),
        boxShadow: const [
          BoxShadow(color: Color(0x471F2A44), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x801F2A44), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -12),
        ],
      ),
      child: Center(
        child: CustomPaint(size: const Size.square(27), painter: _LockMarkPainter()),
      ),
    );
  }
}

class _LockMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final shackle = Path()
      ..moveTo(7.5 * s, 10.4 * s)
      ..lineTo(7.5 * s, 7.7 * s)
      ..arcToPoint(Offset(16.5 * s, 7.7 * s),
          radius: Radius.circular(4.5 * s), clockwise: false)
      ..lineTo(16.5 * s, 10.4 * s);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4.6 * s, 10.2 * s, 14.8 * s, 10.4 * s),
        Radius.circular(3.3 * s),
      ),
      Paint()..color = NoteColors.accent,
    );
    canvas.drawCircle(Offset(12 * s, 15.4 * s), 1.55 * s, Paint()..color = NoteColors.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 错误提示条（dangerSoft 底 + 红字 + 信息图标）。
class _AlertBar extends StatelessWidget {
  const _AlertBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: NoteColors.dangerSoft,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0x29C0483C)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 15, color: NoteColors.danger),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: NoteColors.danger, letterSpacing: .1),
            ),
          ),
        ],
      ),
    );
  }
}

/// 删除确认对话框（白底圆角、取消 / 删除危险色）。
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '删除密码',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: NoteColors.ink),
            ),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 12.5, height: 1.6, color: NoteColors.ink2)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextAction(
                  label: '取消',
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 6),
                TextAction(
                  label: '删除',
                  icon: Icons.delete_outline_rounded,
                  danger: true,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
