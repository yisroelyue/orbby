part of 'home_screen.dart';

/// 命令动作实现。commands.dart 只保留注册信息，具体业务逻辑集中在这里。
extension _HomeScreenCommandActions on _HomeScreenState {
  Future<void> _setPersonality(String name) async {
    final key = name.toLowerCase();
    final description = PersonalityService.presets[key];
    if (description == null) {
      _addLocalMessage('未知性格：$name。可选：${PersonalityService.presets.keys.join('、')}');
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
