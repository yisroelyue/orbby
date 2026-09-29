import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'note/note_theme.dart';
import 'note/notes_view.dart';
import 'note/passwords_view.dart';

enum _NoteTab { notes, passwords }

/// 笔记浮窗外壳（500 × 800 固定窗口）：头部工具栏图标按钮在
/// 「笔记 / 密码本」两个视图间切换（不新增窗口、不新增页面），底部
/// 主按钮随视图变化。安全策略：切回笔记立即锁定密码本、解锁状态下
/// 闲置 5 分钟自动锁定、输错 3 次冷却 30 秒（见 PasswordsView）。
class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  _NoteTab _tab = _NoteTab.notes;
  final _notesKey = GlobalKey<NotesViewState>();
  final _pwKey = GlobalKey<PasswordsViewState>();

  // 头部副标题数据（由子视图回调刷新）
  int _noteTotal = 0;
  int _noteImportant = 0;
  bool _pwLocked = true;
  bool _pwHasVault = false;
  int _pwCount = 0;

  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    // 键盘输入也计入「活跃」，避免长时间打字被闲置锁定误伤。
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _idleTimer?.cancel();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    _pokeIdle();
    return false; // 只观察，不拦截
  }

  void _switchTab(_NoteTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == _NoteTab.notes) {
      // 切走即锁：离开密码本视图立即重新锁定。
      _idleTimer?.cancel();
      _idleTimer = null;
      _pwKey.currentState?.lockNow();
    } else {
      _pwKey.currentState?.onShown();
      _armIdleTimer();
    }
  }

  void _pokeIdle() {
    if (_tab == _NoteTab.passwords && !_pwLocked) _armIdleTimer();
  }

  /// 仅在「密码本视图 + 已解锁」时武装闲置计时（5 分钟）。
  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_tab != _NoteTab.passwords || _pwLocked) return;
    _idleTimer = Timer(const Duration(minutes: 5), () {
      _pwKey.currentState?.lockNow();
    });
  }

  void _onNoteStats(int total, int important) {
    if (!mounted) return;
    setState(() {
      _noteTotal = total;
      _noteImportant = important;
    });
  }

  void _onPwStatus(bool locked, int count, bool hasVault) {
    if (!mounted) return;
    setState(() {
      _pwLocked = locked;
      _pwCount = count;
      _pwHasVault = hasVault;
    });
    _armIdleTimer();
  }

  String get _subtitle {
    if (_tab == _NoteTab.notes) {
      if (_noteTotal == 0) return '暂无笔记';
      return _noteImportant > 0
          ? '$_noteTotal 条笔记 · $_noteImportant 条重要'
          : '$_noteTotal 条笔记';
    }
    if (!_pwHasVault) return '设置主密码后使用';
    if (_pwLocked) return '已锁定 · $_pwCount 个密码';
    return _pwCount > 0 ? '$_pwCount 个密码' : '暂无密码';
  }

  @override
  Widget build(BuildContext context) {
    final isNotes = _tab == _NoteTab.notes;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: NoteColors.panel,
            border: Border.all(color: NoteColors.windowBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHead(isNotes),
              Expanded(
                child: Listener(
                  onPointerDown: (_) => _pokeIdle(),
                  child: IndexedStack(
                    index: isNotes ? 0 : 1,
                    children: [
                      NotesView(key: _notesKey, onStats: _onNoteStats),
                      PasswordsView(key: _pwKey, onStatus: _onPwStatus),
                    ],
                  ),
                ),
              ),
              _buildFoot(isNotes),
            ],
          ),
        ),
      ),
    );
  }

  /// 头部：logo + 标题/副标题（随视图切换）+ 视图切换按钮 + 拖动柄。
  /// 整个头部是拖动区（按钮的手势优先级更高，不影响点击）。
  Widget _buildHead(bool isNotes) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      // 点击头部空白收起笔记编辑器（沿用原整窗点击收起的行为）。
      onTap: () => _notesKey.currentState?.collapseEditor(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 17, 16, 15),
        decoration: const BoxDecoration(
          color: NoteColors.panel,
          border: Border(bottom: BorderSide(color: NoteColors.lineSoft)),
        ),
        child: Row(
          children: [
            const LogoMark(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isNotes ? '笔记' : '密码本',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      letterSpacing: -.1,
                      color: NoteColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle,
                    style: const TextStyle(fontSize: 11.5, color: NoteColors.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _JumpButton(
              icon: isNotes ? Icons.lock_outlined : Icons.article_outlined,
              tooltip: isNotes ? '切换到密码本' : '切换到笔记',
              onTap: () => _switchTab(isNotes ? _NoteTab.passwords : _NoteTab.notes),
            ),
            const SizedBox(width: 4),
            const _DragHandle(),
          ],
        ),
      ),
    );
  }

  /// 底部主按钮：笔记「新建笔记」/ 密码本「新建密码」；锁定态不占位
  /// （设计稿 ④ 无底部按钮），解锁视图全屏居中。
  Widget _buildFoot(bool isNotes) {
    Widget? button;
    if (isNotes) {
      button = PrimaryButton(
        label: '新建笔记',
        onTap: () => _notesKey.currentState?.createNote(),
      );
    } else if (!_pwLocked) {
      button = PrimaryButton(
        label: '新建密码',
        onTap: () => _pwKey.currentState?.startCreate(),
      );
    }
    if (button == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: NoteColors.panel,
        border: Border(top: BorderSide(color: NoteColors.lineSoft)),
      ),
      child: button,
    );
  }
}

/// 头部视图切换按钮：34×34 圆角 10、透明底、只显示图标；
/// hover 时图标转琥珀色并浮出浅底。
class _JumpButton extends StatefulWidget {
  const _JumpButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_JumpButton> createState() => _JumpButtonState();
}

class _JumpButtonState extends State<_JumpButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _hover ? NoteColors.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.icon,
              size: 20,
              color: _hover ? NoteColors.accentDeep : NoteColors.ink3,
            ),
          ),
        ),
      ),
    );
  }
}

/// 六点拖动柄（窗口标题栏拖动的视觉提示，整个头部均可拖动）。
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: Icon(
          Icons.drag_indicator,
          size: 16,
          color: NoteColors.chevron,
        ),
      ),
    );
  }
}
