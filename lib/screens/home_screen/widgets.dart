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

  /// 欢迎页工作台：内容列限宽 540 居中（设计稿 .workbench），自带
  /// 收紧的四周边距（与聊天列表分支的 20/6 分开维护）；整体可滚动
  /// （内容超高时不再强行居中裁切）；不触碰主 Column 的 children
  /// 结构（见文件头纪律）。
  ///
  /// **UI 接入阶段：技能与续接列表为静态假数据**，后续接入——
  /// - 技能 ← _skillPalette.skills（skills.changed 推送热更新）；
  /// - 项目/工作区 ← ChatStorageService 最近会话，点击载入当前 tab。
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
                child: _Workbench(
                  skills: _workbenchDemoSkills,
                  sessions: _workbenchDemoSessions,
                  onFillInput: _fillWorkbenchInput,
                  onManageSkills: () => AppToast.show(
                    _navigatorKey.currentContext ?? context,
                    message: '技能目录：~/.orbby/skills',
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
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

/// 假数据：技能橱窗（真数据 ← _skillPalette.skills，7 个中前 4 直出 + ＋3）
const _workbenchDemoSkills = [
  ChatSkill(name: 'demo', description: '演示技能'),
  ChatSkill(name: '磁盘扫描', description: '扫描磁盘空间占用'),
  ChatSkill(name: '翻译文档', description: '翻译文档内容'),
  ChatSkill(name: '周报', description: '生成周报'),
  ChatSkill(name: '代码审查', description: '审查代码变更'),
  ChatSkill(name: '会议纪要', description: '整理会议纪要'),
  ChatSkill(name: 'SQL 优化', description: '优化 SQL 查询'),
];

/// 假数据：项目 / 工作区续接（真数据 ← ChatStorageService 最近会话）
const _workbenchDemoSessions = [
  _WorkbenchSession(title: 'orbby 主开发会话', path: r'D:\Projects\orbby'),
  _WorkbenchSession(title: '官网改版', path: r'D:\Projects\website'),
];
