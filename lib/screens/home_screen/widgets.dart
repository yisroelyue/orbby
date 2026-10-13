part of 'home_screen.dart';

extension _HomeScreenWidgets on _HomeScreenState {
  Widget _buildChatBody() {
    final isEmpty = _messages.isEmpty && !_isSending;
    final theme = _themeData;
    return Container(
      color: theme.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: _HomeFunctionBar(
              actions: [
                (label: '新建会话', onPressed: _startNewConversation),
                (label: '历史会话', onPressed: _showSessionPicker),
                (label: '应用中心', onPressed: () { HomeScreen.menuChannel.invokeMethod('open_app_center'); }),
                (label: '设置', onPressed: _showAgentSettings),
              ],
            ),
          ),
          if (_showSessionTabs) _buildSessionTabs(),
          Expanded(
            child: isEmpty
                ? _buildWorkbench()
                // 参考稿 .conversation：内容列收窄居中（max 760，收窄幅度
                // 从 640 放宽，两侧留白更小）；输入区与功能栏保持满宽
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildChatList(),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: _buildInputArea(),
          ),
        ],
      ),
    );
  }

  /// 欢迎页工作台：内容列限宽 640 居中，自带收紧的四周边距（与聊天
  /// 列表分支的 20/6 分开维护）；整体可滚动（内容超高时不再强行居中
  /// 裁切）；不触碰主 Column 的 children 结构（见文件头纪律）。
  ///
  /// 数据源：技能 = _skillPalette（AnimatedBuilder 订阅，
  /// skills.changed 推送热更新即时反映）；项目 / 工作区 =
  /// _workspaceHistory（/cd MRU 历史，见 _recordWorkspace）。
  Widget _buildWorkbench() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: AnimatedBuilder(
                  animation: _skillPalette,
                  builder: (context, _) => _Workbench(
                    skills: _skillPalette.skills,
                    workspaces: _workspaceHistory,
                    commands: _palette.commands,
                    onShowUsageGuide: () => _addLocalMessage(
                      HomeUsageGuide.asConversationRecord(_palette.commands),
                    ),
                    onFillInput: _fillWorkbenchInput,
                    onManageSkills: () => AppToast.show(
                      _navigatorKey.currentContext ?? context,
                      message: '技能目录：~/.orbby/skills',
                    ),
                    onResumeWorkspace: _resumeWorkspace,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// 续接行点击：切回该工作区（/cd 语义，作用于当前 tab 的 Node 会话）
  /// 并在 MRU 历史中置顶。目录已被移动/删除时 Node 侧校验失败，toast
  /// 提示、现状不变。
  Future<void> _resumeWorkspace(String path) async {
    if (!mounted) return;
    try {
      final workspace = await AgentService.setWorkspace(
        path,
        sessionId: _current.agentSessionId,
      );
      await _loadWorkspaceLabel();
      await _recordWorkspace(workspace);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          _navigatorKey.currentContext ?? context,
          message: '工作区不可用：$path',
        );
      }
    }
  }

  /// 记录一次工作区切换（/cd 与欢迎页续接共用）：MRU 置顶落盘并刷新
  /// 欢迎页续接列表
  Future<void> _recordWorkspace(String path) async {
    final paths = await WorkspaceHistoryService.record(path);
    if (!mounted) return;
    setState(() =>
        _workspaceHistory = paths.take(_workbenchMaxWorkspaces).toList());
  }

  /// 工作台点击填入输入框并聚焦（不自动发送）：填「/help」「@」这类
  /// 末尾片段由 _onInputChanged 自动唤起对应面板；技能引用尾随空格
  /// = 面板确认语义，不弹面板。
  void _fillWorkbenchInput(String text) {
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputFocus.requestFocus();
  }
}
