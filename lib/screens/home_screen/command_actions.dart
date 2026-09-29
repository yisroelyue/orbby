part of 'home_screen.dart';

/// 错误消息展示：剥掉泛型 Exception 的 "Exception: " 前缀
/// （重写了 toString 的自定义异常如 AgentException 不受影响）
String _cleanErrorMessage(Object error) =>
    error.toString().replaceFirst(RegExp(r'^Exception: '), '');

/// 命令动作实现。commands.dart 只保留注册信息，具体业务逻辑集中在这里。
extension _HomeScreenCommandActions on _HomeScreenState {
  Future<void> _showFilePicker() async {
    try {
      final workspace = await AgentService.workspaceStatus(
        sessionId: _current.agentSessionId,
      );
      final root = Directory(workspace);
      if (!await root.exists()) {
        if (mounted) _addLocalMessage('当前工作区不存在：$workspace');
        return;
      }

      final directories = <String>[];
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! Directory) continue;
        final absolute = entity.path;
        var relative = absolute.startsWith(root.path)
            ? absolute.substring(root.path.length)
            : absolute;
        relative = relative.replaceFirst(RegExp(r'^[\\/]'), '').replaceAll('\\', '/');
        if (relative.isNotEmpty) directories.add(relative);
        if (directories.length >= 5000) break;
      }
      directories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      final selected = await _pickWorkspaceFile(directories);
      if (selected != null && mounted) {
        final currentText = _inputController.text;
        final slashIndex = currentText.lastIndexOf('/');
        final prefix = slashIndex < 0
            ? ''
            : currentText.substring(0, slashIndex);
        _setInputText('$prefix$selected ');
        _inputFocus.requestFocus();
      }
    } catch (error) {
      if (mounted) _addLocalMessage('读取工作区文件失败：${_cleanErrorMessage(error)}');
    }
  }

  Future<String?> _pickWorkspaceFile(List<String> directories) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _WorkspaceFilePickerDialog(files: directories),
    );
  }

  Future<void> _setPersonality(String name) async {
    final (key, candidates) = PersonalityService.resolve(name);
    if (key == null) {
      if (name.trim().isEmpty) {
        _addLocalMessage('可选性格：${PersonalityService.presets.keys.join('、')}（支持前缀，如 /personality h）');
        return;
      }
      final ambiguity = candidates.length > 1 ? '（前缀匹配到多个：${candidates.join('、')}）' : '';
      _addLocalMessage('未知性格：$name$ambiguity。可选：${PersonalityService.presets.keys.join('、')}（支持前缀）');
      return;
    }
    await PersonalityService.save(key);
    if (mounted) _addLocalMessage('性格已切换为 $key');
  }

  Future<void> _showAgentStatus() async {
    try {
      final status = await AgentService.status(sessionId: _current.agentSessionId);
      if (!mounted) return;
      _addLocalMessage('上下文：${status['totalTokens'] ?? 0}/${status['maxTokens'] ?? 0} tokens（${status['usagePercent'] ?? 0}%）\n'
          '消息：${status['messageCount'] ?? 0}，事件：${status['eventCount'] ?? 0}\n'
          '字符：${status['contextChars'] ?? 0}，轮次：${status['turn'] ?? 0}，步骤：${status['step'] ?? 0}');
    } catch (e) {
      if (mounted) _addLocalMessage('获取会话状态失败: $e');
    }
  }

  Future<void> _showPermissionStatus() async {
    final status = await AgentService.permissionStatus();
    if (!mounted) return;
    final mode = status['mode'] ?? 'ask';
    _addLocalMessage('当前授权模式：$mode');
  }

  /// /cd：切换 Agent 工作区（Node 侧校验；仅当前 runtime 生命周期有效）。
  /// 空参数查看当前工作区；相对路径由 Node 侧按当前工作区解析。
  Future<void> _changeWorkspace(String path) async {
    // 用户复制的 Windows 路径常带包裹引号，剥掉再交 Node 解析；
    // 工作区按会话隔离：读写都作用于当前 tab 的 agentSessionId
    final target = path.trim().replaceAll('"', '');
    final sid = _current.agentSessionId;
    if (target.isEmpty) {
      try {
        final workspace = await AgentService.workspaceStatus(sessionId: sid);
        if (mounted) _addLocalMessage('当前工作区：$workspace');
      } catch (e) {
        if (mounted) _addLocalMessage('查询工作区失败：${_cleanErrorMessage(e)}');
      }
      return;
    }
    try {
      final workspace = await AgentService.setWorkspace(target, sessionId: sid);
      await _loadWorkspaceLabel();
      if (mounted) _addLocalMessage('工作区已切换：$workspace');
    } catch (e) {
      if (mounted) _addLocalMessage('切换工作区失败：${_cleanErrorMessage(e)}');
    }
  }

  void _setPermissionMode(String mode, String message) {
    AgentService.setPermissionMode(mode);
    _addLocalMessage(message);
  }

  /// /new：另开一个新的会话 tab（旧会话原地保留，可经 tab 栏切回）
  void _startNewConversation() {
    if (!mounted) return;
    _openNewSessionTab();
  }

  /// /close：关闭当前会话 tab；最后一个 tab 关闭后由现有逻辑补充空 tab。
  void _closeCurrentSessionTab() {
    if (!mounted) return;
    _closeSessionTab(_activeIndex);
  }

  Future<void> _clearCurrentConversation() async {
    if (!mounted) return;
    final conversationId = _conversation?.id;
    // 等待正在进行的快照落盘，再删除当前会话，避免保存链把旧历史重新写回来。
    await _saveChain;
    if (conversationId != null) {
      await ChatStorageService.delete(conversationId);
    }
    if (!mounted) return;
    AgentService.resetConversation(sessionId: _current.agentSessionId);
    setState(() {
      _conversation = null;
      _messages.clear();
      _queuedTexts.clear();
      _dismissQuestionCard();
      // 内容整体换源，旧的滚动记录对空列表无意义
      _current.resetScrollState();
    });
    _attachmentCtrl.clear();
  }

  /// /clear-session：删除全部历史会话文件，关闭所有多余 tab 只留一个空 tab。
  /// 不走 [_closeSessionTab]——那里会落盘，会把刚删除的会话文件写回来
  Future<void> _clearAllSessions() async {
    if (!mounted) return;
    await ChatStorageService.deleteAll();
    if (!mounted) return;
    // 先取消运行中的流并回收各会话的 Node 上下文（WS 发送在 setState 外做）
    for (final view in _views) {
      if (view.isSending) AgentService.cancelCurrent(sessionId: view.agentSessionId);
      AgentService.resetConversation(sessionId: view.agentSessionId);
      // dispose 后必须置 null：取消触发的流式收尾还会走 _dismissQuestionCard(view)
      view.questionCtrl?.dispose();
      view.questionCtrl = null;
      view.questionId = null;
      view.attachmentCtrl.dispose();
    }
    setState(() {
      _views.clear();
      _views.add(ChatSessionView(agentSessionId: AgentService.newSessionId()));
      _activeIndex = 0;
      _inputController.clear();
    });
  }

  void _retryLastMessage() {
    if (!mounted || _isSending) return;
    final lastUser = _messages.lastIndexWhere((m) => m.isUser);
    if (lastUser < 0) return;
    final message = _messages[lastUser];
    final text = message.text;
    final attachments = List<ChatAttachment>.of(message.attachments);
    // 丢掉最后一条用户消息及其后的所有回复，重新发送。
    setState(() => _messages.removeRange(lastUser, _messages.length));
    _sendText(text, attachments: attachments);
  }
}

class _WorkspaceFilePickerDialog extends StatefulWidget {
  const _WorkspaceFilePickerDialog({required this.files});

  final List<String> files;

  @override
  State<_WorkspaceFilePickerDialog> createState() =>
      _WorkspaceFilePickerDialogState();
}

class _WorkspaceFilePickerDialogState
    extends State<_WorkspaceFilePickerDialog> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _searchFocusNode = FocusNode();
  int _selectedIndex = 0;

  List<String> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.files;
    return widget.files
        .where((file) => file.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_resetSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _resetSelection() => setState(() => _selectedIndex = 0);

  void _move(int delta) {
    final count = _filtered.length;
    if (count == 0) return;
    setState(() => _selectedIndex = (_selectedIndex + delta + count) % count);
  }

  void _focusList() {
    _focusNode.requestFocus();
  }

  void _confirm() {
    final files = _filtered;
    if (files.isNotEmpty) Navigator.of(context).pop(files[_selectedIndex]);
  }

  @override
  Widget build(BuildContext context) {
    const panel = Color(0xFFFFFFFF);
    const ink = Color(0xFF1F2937);
    const secondary = Color(0xFF4B5563);
    const muted = Color(0xFF6B7280);
    const sunken = Color(0xFFF3F4F6);
    final files = _filtered;
    final index = files.isEmpty ? 0 : _selectedIndex.clamp(0, files.length - 1);
    return Dialog(
      backgroundColor: panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 620,
        height: 560,
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            // 搜索框获得焦点时保留上下键的文字光标行为；↓进入目录列表。
            if (_searchFocusNode.hasFocus) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _focusList();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (_selectedIndex == 0) {
                _searchFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              _move(-1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _move(1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              _confirm();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('工作区目录（${files.length}）', style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18, color: muted)),
              ]),
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索文件名或路径',
                  prefixIcon: const Icon(Icons.search, color: muted),
                  isDense: true,
                  filled: true,
                  fillColor: sunken,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: files.isEmpty
                    ? const Center(child: Text('没有匹配的目录', style: TextStyle(color: muted)))
                    : ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (_, i) => InkWell(
                          onTap: () => Navigator.of(context).pop(files[i]),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: i == index ? const Color(0xFFE8F0FE) : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                            child: Text(files[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: secondary, fontSize: 13, fontFamily: _fontFamily)),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              const Text('↑↓ 选择  Enter 插入  Esc 关闭', style: TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_resetSelection);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
