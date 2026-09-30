part of 'home_screen.dart';

/// 输入区：输入框 UI、输入历史（↑/↓ 浏览）、命令面板确认、
/// 以及命令面板/提问卡片对键盘导航的接管。
extension _HomeScreenInput on _HomeScreenState {
  Future<void> _loadWorkspaceLabel() async {
    try {
      final workspace = await AgentService.workspaceStatus(
        sessionId: _current.agentSessionId,
      );
      final normalized = workspace.replaceAll('\\', '/');
      final parts = normalized
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      if (!mounted || parts.isEmpty) return;
      setState(() => _workspaceLabel = parts.last);
    } catch (_) {
      // 工作区查询失败时保留默认标签，不影响输入。
    }
  }

  Widget _buildInputArea() {
    final theme = _themeData;
    final inputInk = theme.isDark ? const Color(0xFFE2E4E8) : theme.ink;
    final inputMuted = theme.isDark ? const Color(0xFFCDD0D6) : theme.ink2;
    final inputHint = theme.isDark ? const Color(0xFFB9BEC7) : theme.ink3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // '/' 命令提示列表，展开在输入框正上方
        CommandPalette(controller: _palette, onConfirm: _confirmCommand),
        // '@' 技能提示列表：与命令面板同位、按触发字符互斥显示，
        // 不可见时自身为零高度空盒（children 位置稳定，不破坏索引 diff）
        SkillPalette(controller: _skillPalette, onConfirm: _confirmSkill),
        // Agent 提问卡片：无挂起提问时用零高度盒子占位。
        // 不用 `if (...)` 条件展开——Column 的 children 按索引 diff（无 key），
        // 卡片出现/消失会让它后面的附件区与输入框整体错位并被销毁重建
        // （输入文字、焦点、附件状态全丢）
        _questionCtrl != null
            ? AgentQuestionPanel(
                controller: _questionCtrl!,
                onSubmit: _submitAgentAnswer,
                onSkip: _skipAgentQuestion,
              )
            : const SizedBox.shrink(),
        // 粘贴的图片附件缩略图（无附件且无提示时为零高度空盒）
        ChatAttachmentPreview(
          controller: _attachmentCtrl,
          onOpen: _viewAttachment,
        ),
        // 聚焦态光环需要跟随输入框焦点重绘（参考稿 composer.focus）
        ListenableBuilder(
          listenable: _inputFocus,
          builder: (context, _) {
            return Container(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
              decoration: BoxDecoration(
                color: theme.isDark
                    ? Colors.transparent
                    : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(18),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: theme.isDark ? const Color(0xFF303238) : theme.surface,
                  border: Border.all(
                    color: theme.isDark ? Colors.transparent : theme.line,
                  ),
                  boxShadow: const <BoxShadow>[],
                ),
                child: Focus(
                  onKeyEvent: _handleKeyEvent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        minLines: 2,
                        maxLines: 10,
                        enabled: true,
                        cursorColor: theme.isDark ? inputInk : theme.accentDeep,
                        style: TextStyle(
                          color: inputInk,
                          fontSize: 15,
                          height: 1.65,
                          letterSpacing: 0.3,
                          fontFamily: _fontFamily,
                        ),
                        decoration: InputDecoration(
                          hint: _isSending
                              ? null
                              : RichText(
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: inputHint,
                                      fontSize: 15,
                                      letterSpacing: 0.3,
                                      fontFamily: _fontFamily,
                                    ),
                                    children: [
                                      const TextSpan(
                                        text: '描述你的需求，使用 /help 查看常用命令及说明，使用 @ 调用技能。',
                                      ),
                                      // const TextSpan(text: '描述你的需求，'),
                                      // TextSpan(
                                      //   text: '/help',
                                      //   style: const TextStyle(
                                      //     color: Color(0xFF3665DD),
                                      //   ),
                                      // ),
                                      // const TextSpan(text: ' 查看常用命令，'),
                                      // TextSpan(
                                      //   text: '@',
                                      //   style: const TextStyle(
                                      //     color: Color(0xFF3665DD),
                                      //   ),
                                      // ),
                                      // const TextSpan(text: ' 调用技能。'),
                                    ],
                                  ),
                                ),
                          hintStyle: TextStyle(
                            color: inputHint,
                            fontSize: 15,
                            letterSpacing: 0.3,
                            fontFamily: _fontFamily,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.fromLTRB(
                            14,
                            20,
                            8,
                            12,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        child: Container(
                          padding: const EdgeInsets.only(left: 14, right: 20),
                          // alignment 让 Row 在 48 高度内垂直居中
                          //（松约束下 Row 自身 wrap 高度会贴顶，须由容器对齐）
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Tooltip(
                                    message: '当前工作区，使用/cd命令切换',
                                    preferBelow: false,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    textStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SvgPicture.asset(
                                          'assets/svg/工作区.svg',
                                          width: 16,
                                          height: 16,
                                          colorFilter: ColorFilter.mode(inputMuted, BlendMode.srcIn),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            _workspaceLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: inputMuted,
                                              fontSize: 12,
                                              letterSpacing: 0.2,
                                              fontFamily: _fontFamily,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: '当前模型（暂不支持切换）',
                                preferBelow: false,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                textStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SvgPicture.asset(
                                        'assets/svg/大模型.svg',
                                        width: 16,
                                        height: 16,
                                        colorFilter: ColorFilter.mode(inputMuted, BlendMode.srcIn),
                                      ),
                                      const SizedBox(width: 6),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 130,
                                        ),
                                        child: Text(
                                          _modelLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: inputMuted,
                                            fontSize: 12,
                                            letterSpacing: 0.2,
                                            fontFamily: _fontFamily,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 17,
                                        color: inputMuted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: '发送消息',
                                preferBelow: false,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                textStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _inputController,
                                  builder: (context, value, _) => _SendButton(
                                    onPressed: _sendMessage,
                                    active: value.text.trim().isNotEmpty,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 确认（Enter/Tab/点击）命令：清空输入并按 behavior 分派。
  /// prepareInput 类命令不执行动作，只把 `/命令名 ` 写回输入框；
  /// immediate 类执行 execute。键盘路径不传参取选中项；点击路径传被点的命令
  void _confirmCommand([ChatCommand? cmd]) {
    cmd ??= _palette.confirm();
    if (cmd == null) return;
    // /file 需要保留前面的 /cd 路径，选择目录后只替换最后一个命令片段。
    if (cmd.name != 'file') _inputController.clear();
    if (cmd.behavior == ChatCommandBehavior.prepareInput) {
      _prepareInputCommand(cmd);
    } else {
      cmd.execute();
    }
  }

  void _addInputHistory(String text) {
    if (text.isEmpty) return;
    if (_inputHistory.isNotEmpty && _inputHistory.last == text) {
      _historyIndex = -1;
      _historyDraft = '';
      return;
    }
    _inputHistory.add(text);
    _historyIndex = -1;
    _historyDraft = '';
  }

  void _showPreviousInput() {
    if (_inputHistory.isEmpty) return;
    if (_historyIndex == -1) _historyDraft = _inputController.text;
    if (_historyIndex < _inputHistory.length - 1) _historyIndex++;
    _setInputText(_inputHistory[_inputHistory.length - 1 - _historyIndex]);
  }

  void _showNextInput() {
    if (_historyIndex == -1) return;
    if (_historyIndex > 0) {
      _historyIndex--;
      _setInputText(_inputHistory[_inputHistory.length - 1 - _historyIndex]);
    } else {
      _historyIndex = -1;
      _setInputText(_historyDraft);
      _historyDraft = '';
    }
  }

  void _setInputText(String text) {
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_isSending &&
        key == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed) {
      AgentService.cancelCurrent(sessionId: _current.agentSessionId);
      return KeyEventResult.handled;
    }

    // Ctrl+V：优先尝试剪贴板图片，
    // 无图片回退普通文本粘贴；Alt+V：仅尝试图片。须在命令面板分支之前
    // 判断——准备态输入框里是 '/' 前缀文本，粘贴图片仍要生效。
    if (key == LogicalKeyboardKey.keyV) {
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      final alt = HardwareKeyboard.instance.isAltPressed;
      if (ctrl && !alt) {
        _pasteIntoInput(imageOnly: false);
        return KeyEventResult.handled;
      }
      if (alt && !ctrl) {
        _pasteIntoInput(imageOnly: true);
        return KeyEventResult.handled;
      }
    }

    // 命令面板可见时，导航键优先于输入框默认行为
    if (_palette.visible) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _palette.movePrevious();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _palette.moveNext();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _palette.dismiss();
        return KeyEventResult.handled;
      }
      final isConfirm =
          key == LogicalKeyboardKey.tab ||
          (key == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed);
      if (isConfirm) {
        _confirmCommand();
        return KeyEventResult.handled;
      }
    }

    // '@' 技能面板可见时，同款导航接管（与命令面板经 _onInputChanged
    // 互斥路由，不会同时 visible；分支并列仅为防重）
    if (_skillPalette.visible) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _skillPalette.movePrevious();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _skillPalette.moveNext();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _skillPalette.dismiss();
        return KeyEventResult.handled;
      }
      final isConfirm =
          key == LogicalKeyboardKey.tab ||
          (key == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed);
      if (isConfirm) {
        _confirmSkill();
        return KeyEventResult.handled;
      }
    }

    // Agent 提问卡片挂起时接管导航键（显式唤起的命令面板优先级更高，见上）。
    // 输入框正在打字时不接管 ↑↓/Enter，避免拦截用户排队发送的消息；Esc 始终可跳过提问。
    if (_questionCtrl != null) {
      if (key == LogicalKeyboardKey.escape) {
        _cancelAgentQuestion();
        return KeyEventResult.handled;
      }
      if (_inputController.text.isEmpty) {
        if (key == LogicalKeyboardKey.arrowUp) {
          _questionCtrl!.navigate(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _questionCtrl!.navigate(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          if (_questionCtrl!.confirmCurrent()) _submitAgentAnswer();
          return KeyEventResult.handled;
        }
      }
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _showPreviousInput();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _showNextInput();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _sendMessage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 窗口级按键兜底：焦点不在输入框时（点过聊天区其他可聚焦控件等）也能终止。
  /// 按键事件沿焦点链从 primaryFocus 向上冒泡，输入框 handler 在更内层、
  /// 已 handled 的键不会到这一层；SelectionArea 的复制快捷键同样在更内层，
  /// 先于本层生效。此处只兜底：Ctrl+C 终止任务、Esc 取消提问/终止任务/关闭窗口
  /// （挂起提问与发送中优先于关窗；弹窗挂 navigator 层，焦点链不经过本层，
  /// 其 Esc 由弹窗自行消费）。navigator 层的大图/文档查看器同理，不会误关窗。
  KeyEventResult _handleWindowKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_isSending &&
        key == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed) {
      AgentService.cancelCurrent(sessionId: _current.agentSessionId);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_questionCtrl != null) {
        _cancelAgentQuestion();
        return KeyEventResult.handled;
      }
      if (_isSending) {
        AgentService.cancelCurrent(sessionId: _current.agentSessionId);
        return KeyEventResult.handled;
      }
      // 无挂起交互时 Esc 收起菜单窗口：经 hub 的 close_menu（同步 _menuVisible，
      // 防下次快捷键 toggle 误判），menu 常驻只 hide、engine 状态（含输入草稿）保留。
      HomeScreen.menuChannel.invokeMethod('close_menu');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // =========================================================================
  // 剪贴板粘贴：Ctrl+V 优先图片、无图回退文本；Alt+V 仅尝试图片
  // =========================================================================

  /// 打开附件（图片看大图，文件调系统程序；经 navigatorKey context，
  /// HomeScreen 自身 context 弹窗找不到 MaterialLocalizations）
  void _viewAttachment(ChatAttachment attachment) {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    openAttachment(navContext, attachment);
  }

  Future<void> _pasteIntoInput({required bool imageOnly}) async {
    if (_isSending) {
      // 请求进行中禁止追加附件；纯文本粘贴不受影响
      if (imageOnly) {
        _attachmentCtrl.showHint('回复进行中，请稍后再添加附件');
      } else {
        await _pasteTextIntoInput();
      }
      return;
    }
    ClipboardImageRead? read;
    String? unsupportedName;
    try {
      final result = await ClipboardImageService.readFromClipboard();
      read = result.read;
      unsupportedName = result.unsupportedFileName;
    } catch (_) {
      // 通道异常按"无附件"处理，回退文本粘贴
    }
    if (read != null) {
      await _attachmentCtrl.add(read);
      _inputFocus.requestFocus();
      return;
    }
    if (imageOnly) {
      // Alt+V 仅试附件：不支持类型的文件在这里给出提示
      if (unsupportedName != null) _hintUnsupported(unsupportedName);
      return;
    }
    // Ctrl+V：不支持的文件优先回退文本粘贴；无文本可粘时才提示不支持
    final pastedText = await _pasteTextIntoInput();
    if (unsupportedName != null && !pastedText) {
      _hintUnsupported(unsupportedName);
    }
  }

  void _hintUnsupported(String fileName) {
    _attachmentCtrl.showHint('「$fileName」暂不支持作为附件发送（当前支持图片、文本、PDF）');
  }

  /// 手动把剪贴板文本插入输入框（接管 Ctrl+V 后 TextField 默认粘贴不再触发）。
  /// 返回是否有文本被插入（供不支持文件粘贴的提示逻辑判断）。
  Future<bool> _pasteTextIntoInput() async {
    final data = await Clipboard.getData('text/plain');
    final pasted = data?.text;
    if (pasted == null || pasted.isEmpty) return false;
    final value = _inputController.value;
    // 输入框未聚焦时 selection 可能未挂载（offset -1），退化为追加到末尾
    final base = value.selection.isValid && value.selection.baseOffset >= 0
        ? value.selection.baseOffset
        : value.text.length;
    final extent = value.selection.isValid && value.selection.extentOffset >= 0
        ? value.selection.extentOffset
        : value.text.length;
    final start = base <= extent ? base : extent;
    final end = base <= extent ? extent : base;
    final next = value.text.replaceRange(start, end, pasted);
    _inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + pasted.length),
    );
    return true;
  }
}

/// 发送按钮（参考稿 .send）：30px 琥珀圆钮 + 墨色纸飞机，两套主题同款
class _SendButton extends StatefulWidget {
  const _SendButton({required this.onPressed, required this.active});

  final VoidCallback onPressed;
  final bool active;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 34,
          height: 34,
          child: SvgPicture.asset(
            widget.active
                ? 'assets/svg/send_up_active.svg'
                : 'assets/svg/send_up.svg',
            width: 34,
            height: 34,
          ),
        ),
      ),
    );
  }
}
