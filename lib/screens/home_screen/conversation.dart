part of 'home_screen.dart';

/// 会话生命周期：落盘保存、本地消息、历史会话切换、会话内容复制、
/// 以及落盘 JSON 字段的解码还原。
extension _HomeScreenConversation on _HomeScreenState {
  /// 当前对话落盘（~/.orbby/task）；空对话不创建文件。
  /// 首轮发送时创建会话，标题取第一条用户消息。
  /// 保存请求串行执行（_saveChain），避免两次快照交错落盘；
  /// 链内吞错——一环失败不能毒化后续所有保存。
  Future<void> _saveConversation() {
    _saveChain = _saveChain.then((_) async {
      try {
        var msgs = <Map<String, String>>[
          for (final m in _messages)
            // local 消息（命令结果）是瞬时提示，不落盘：
            // 否则重载会话后 local 标志丢失，会混进下次发送的 history
            if ((m.text.isNotEmpty || m.toolEvents.isNotEmpty || m.attachments.isNotEmpty) && !m.local)
              {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
                // 附件只落引用元数据（路径等），Base64 绝不入盘
                if (m.attachments.isNotEmpty) 'attachments': jsonEncode(m.attachments.map((e) => e.toJson()).toList()),
                if (m.fileChanges.isNotEmpty) 'fileChanges': jsonEncode(m.fileChanges.map((e) => e.toJson()).toList()),
                if (m.toolEvents.isNotEmpty) 'toolEvents': jsonEncode(m.toolEvents.map((e) => e.toJson()).toList()),
              },
        ];
        if (msgs.isEmpty) return;
        _conversation ??= ChatConversation(
          id: ChatStorageService.newConversationId(),
          title: _messages
              .firstWhere((m) => m.isUser && !m.local,
                  orElse: () => _messages.first)
              .text,
        );
        final conv = _conversation!;
        if (conv.title.isEmpty) {
          conv.title = msgs.first['content'] ?? '未命名会话';
        }
        conv.messages
          ..clear()
          ..addAll(msgs);
        await ChatStorageService.save(conv);
      } catch (_) {
        // 落盘失败静默跳过，聊天主流程不受影响
      }
    });
    return _saveChain;
  }

  /// 插入一条本地 assistant 消息（命令结果等），并落盘
  void _addLocalMessage(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: false, local: true));
    });
    _scrollToBottom(force: true);
    _saveConversation();
  }

  Future<void> _copyConversationJson() async {
    if (!mounted) return;
    if (_conversation == null) {
      _addLocalMessage('当前还没有可复制的会话。');
      return;
    }
    await _saveConversation();
    if (!mounted) return;
    final json = const JsonEncoder.withIndent('  ').convert(_conversation!.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    _addLocalMessage('当前会话已复制到剪贴板。');
  }

  Future<void> _copyConversationText() async {
    if (!mounted) return;
    final messages = _messages.where((message) => !message.local && message.text.isNotEmpty).toList();
    if (messages.isEmpty) {
      _addLocalMessage('当前还没有可复制的会话。');
      return;
    }
    final text = messages.map((message) {
      final role = message.isUser ? '用户' : '助手';
      return '$role：\n${message.text}';
    }).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    _addLocalMessage('当前会话文本已复制到剪贴板。');
  }

  /// /session：打开历史会话弹窗，选择后切换（切换前自动保存当前会话）
  Future<void> _showSessionPicker() async {
    if (!mounted) return;
    if (_isSending) {
      _addLocalMessage('回复进行中，结束后再切换会话。');
      return;
    }
    await _saveConversation();
    final conversations = await ChatStorageService.loadAll();
    if (!mounted) return;
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final selected = await showDialog<ChatConversation>(
      context: navContext,
      barrierColor: Colors.black54,
      builder: (_) => SessionPickerDialog(conversations: conversations),
    );
    if (selected == null || !mounted) return;
    final conv = await ChatStorageService.load(selected.id) ?? selected;
    // agent 上下文由下次发送携带的 history 重建
    AgentService.resetConversation();
    // 切换会话后当前输入的附件不再属于新会话，一并清理
    _attachmentCtrl.clear();
    setState(() {
      _conversation = conv;
      _messages
        ..clear()
        ..addAll([
          for (final m in conv.messages)
            _ChatMessage(
              text: m['content'] ?? '',
              isUser: m['role'] == 'user',
              attachments: _decodeAttachments(m['attachments']),
            )
              ..fileChanges.addAll(_decodeChanges(m['fileChanges']))
              ..toolEvents.addAll(_decodeToolEvents(m['toolEvents'])),
        ]);
    });
    _scrollToBottom(force: true);
  }

  List<ChatAttachment> _decodeAttachments(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => ChatAttachment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<FileChangePreview> _decodeChanges(String? raw) { if (raw == null || raw.isEmpty) return []; try { final list = jsonDecode(raw) as List; return list.whereType<Map>().map((e) => FileChangePreview.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) { return []; } }

  List<_ToolEvent> _decodeToolEvents(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) => _ToolEvent.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }
}
