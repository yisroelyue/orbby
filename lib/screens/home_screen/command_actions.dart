part of 'home_screen.dart';

/// 错误消息展示：剥掉泛型 Exception 的 "Exception: " 前缀
/// （重写了 toString 的自定义异常如 AgentException 不受影响）
String _cleanErrorMessage(Object error) =>
    error.toString().replaceFirst(RegExp(r'^Exception: '), '');

/// 命令动作实现。commands.dart 只保留注册信息，具体业务逻辑集中在这里。
extension _HomeScreenCommandActions on _HomeScreenState {
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
      final status = await AgentService.status();
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

  /// /cd：切换 Agent 工作区（Node 侧校验目录并持久化）。
  /// 空参数查看当前工作区；相对路径由 Node 侧按当前工作区解析。
  Future<void> _changeWorkspace(String path) async {
    // 用户复制的 Windows 路径常带包裹引号，剥掉再交 Node 解析
    final target = path.trim().replaceAll('"', '');
    if (target.isEmpty) {
      try {
        final workspace = await AgentService.workspaceStatus();
        if (mounted) _addLocalMessage('当前工作区：$workspace');
      } catch (e) {
        if (mounted) _addLocalMessage('查询工作区失败：${_cleanErrorMessage(e)}');
      }
      return;
    }
    try {
      final workspace = await AgentService.setWorkspace(target);
      if (mounted) _addLocalMessage('工作区已切换：$workspace');
    } catch (e) {
      if (mounted) _addLocalMessage('切换工作区失败：${_cleanErrorMessage(e)}');
    }
  }

  void _setPermissionMode(String mode, String message) {
    AgentService.setPermissionMode(mode);
    _addLocalMessage(message);
  }

  void _startNewConversation() {
    if (!mounted) return;
    AgentService.recreate();
    // 旧会话文件保留，下次发送创建新会话。
    setState(() {
      _conversation = null;
      _messages.clear();
      _dismissQuestionCard();
    });
    _attachmentCtrl.clear();
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
    AgentService.resetConversation();
    setState(() {
      _conversation = null;
      _messages.clear();
      _queuedTexts.clear();
      _dismissQuestionCard();
    });
    _attachmentCtrl.clear();
  }

  Future<void> _clearAllSessions() async {
    if (!mounted) return;
    await ChatStorageService.deleteAll();
    if (!mounted) return;
    AgentService.recreate();
    setState(() {
      _conversation = null;
      _messages.clear();
      _queuedTexts.clear();
      _dismissQuestionCard();
    });
    _attachmentCtrl.clear();
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
