part of 'home_screen.dart';

/// 输入区：输入框 UI、输入历史（↑/↓ 浏览）、命令面板确认、
/// 以及命令面板/提问卡片对键盘导航的接管。
extension _HomeScreenInput on _HomeScreenState {
  Widget _buildInputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // '/' 命令提示列表，展开在输入框正上方
        CommandPalette(
          controller: _palette,
          onConfirm: _confirmCommand,
        ),
        // Agent 提问卡片：无挂起提问时为零高度空盒，不占位
        if (_questionCtrl != null)
          AgentQuestionPanel(
            controller: _questionCtrl!,
            onSubmit: _submitAgentAnswer,
            onSkip: _skipAgentQuestion,
          ),
        // 粘贴的图片附件缩略图（无附件且无提示时为零高度空盒）
        ChatAttachmentPreview(
          controller: _attachmentCtrl,
          onOpen: _viewAttachment,
        ),
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            controller: _inputController,
            focusNode: _inputFocus,
            minLines: 1,
            maxLines: 10,
            enabled: true,
            cursorColor: Colors.white,
            style: TextStyle(
                color: _inputText,
                fontSize: 14,
                fontFamily: _fontFamily),
            decoration: InputDecoration(
              hintText: _isSending ? '' : 'Type something or use /help to list commands',
              hintStyle: TextStyle(
                  color: _inputHint,
                  fontSize: 14,
                  fontFamily: _fontFamily),
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              filled: true,
              fillColor: _inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide.none,
              ),
              suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton(
                        icon: SvgPicture.asset('assets/svg/发送.svg',
                            width: 22, height: 22),
                        onPressed: _sendMessage,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
            ),
          ),
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
    _inputController.clear();
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
      AgentService.cancelCurrent();
      return KeyEventResult.handled;
    }

    // Ctrl+V：优先尝试剪贴板图片（/image-analyze 准备态的关键入口），
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
      final isConfirm = key == LogicalKeyboardKey.tab ||
          (key == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed);
      if (isConfirm) {
        _confirmCommand();
        return KeyEventResult.handled;
      }
    }

    // Agent 提问卡片挂起时接管导航键（显式唤起的命令面板优先级更高，见上）。
    // 输入框正在打字时不接管 ↑↓/Enter，避免拦截用户排队发送的消息；Esc 始终可跳过提问。
    if (_questionCtrl != null) {
      if (key == LogicalKeyboardKey.escape) {
        _skipAgentQuestion();
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
