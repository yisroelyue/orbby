part of 'home_screen.dart';

/// 命令动作实现。commands.dart 只保留注册信息，具体业务逻辑集中在这里。
extension _HomeScreenCommandActions on _HomeScreenState {
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

  void _clearCurrentConversation() {
    if (!mounted) return;
    AgentService.resetConversation();
    setState(() {
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
