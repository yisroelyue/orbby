part of 'home_screen.dart';

/// Agent 链路：消息发送入口、核心发送流程（chatStream 消费）、
/// /compact 上下文压缩、提问卡片的提交/跳过/收起。
extension _HomeScreenAgent on _HomeScreenState {
  /// /compact：压缩上下文，摘要作为一条本地回复显示
  Future<void> _runCompact() async {
    if (!mounted || _isSending) return;
    if (_messages.isEmpty) {
      _addLocalMessage('当前没有对话可压缩。');
      return;
    }
    setState(() {
      _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
      _isSending = true;
    });
    _scrollToBottom(force: true);
    try {
      final summary = await AgentService.compact();
      if (!mounted) return;
      setState(() => _messages.last.text = summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.last.text = '压缩失败: $e');
    }
    if (mounted) {
      setState(() {
        _messages.last.streaming = false;
        _isSending = false;
      });
    }
    _saveConversation();
    _focusInput();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    // 输入为空且无附件不发送；有附件时允许说明为空（用默认文案）
    if (text.isEmpty && _attachmentCtrl.isEmpty) return;

    if (text.startsWith('/')) {
      // prepareInput 命令带后缀（如 `/image-analyze 找出布局问题`）：
      // 剥离前缀走图片分析发送流程（精确匹配不到，须在 findExact 之前判断）
      final prepare = _matchPrepareCommand(text);
      if (prepare != null) {
        await _sendImageAnalyze(prepare.$2);
        return;
      }
      _addInputHistory(text);
      // '/' 开头按命令处理：精确匹配则按 behavior 分派，否则丢弃（不把命令残片发给 AI）
      final cmd = _palette.findExact(text.substring(1));
      _inputController.clear();
      if (cmd != null) {
        if (cmd.behavior == ChatCommandBehavior.prepareInput) {
          _prepareInputCommand(cmd);
        } else {
          cmd.execute();
        }
      }
      return;
    }

    _addInputHistory(text);

    if (_attachmentCtrl.isNotEmpty) {
      if (_isSending) {
        _attachmentCtrl.showHint('回复进行中，请等待当前回复完成再发送附件');
        return;
      }
      // 未输入文字时按附件构成选默认提问：纯图片走图片文案，含文档走通用文案
      final isImageOnly = _attachmentCtrl.items.every((a) => a.isImage);
      final prompt = text.isEmpty
          ? (isImageOnly ? _defaultImagePrompt : _defaultAttachmentPrompt)
          : text;
      await _sendWithAttachments(prompt);
      return;
    }

    _inputController.clear();
    if (_isSending) {
      setState(() => _queuedTexts.add(text));
      return;
    }
    await _sendText(text);
  }

  /// /image-analyze 发送流程：说明可空（用默认文案）；无附件提示先粘贴，
  /// 不调用 AI
  Future<void> _sendImageAnalyze(String instruction) async {
    if (_attachmentCtrl.isEmpty) {
      _attachmentCtrl.showHint('请先粘贴图片（Ctrl+V），再执行图片分析');
      _inputFocus.requestFocus();
      return;
    }
    if (_isSending) {
      _attachmentCtrl.showHint('回复进行中，请等待当前回复完成再发送图片');
      return;
    }
    await _sendWithAttachments(instruction.isEmpty ? _defaultImagePrompt : instruction);
  }

  /// 带附件发送的统一入口：附件编码并转移 → _sendText。
  /// 附件未就绪时保留在 controller，方便用户处理后重发。
  Future<void> _sendWithAttachments(String text) async {
    _inputController.clear();
    final attachments = await _attachmentCtrl.takeReady();
    if (attachments.isEmpty) {
      _attachmentCtrl.showHint('附件尚未就绪，请稍候再发送');
      return;
    }
    await _sendText(text, attachments: attachments);
  }

  /// 核心发送流程：追加用户消息并流式请求回复（输入发送与 /retry 共用）
  Future<void> _sendText(String text, {List<ChatAttachment> attachments = const []}) async {
    if (_isSending) {
      _queuedTexts.add(text);
      return;
    }

    // 剔除文件已失效的附件（重载会话后可能被清理）
    final valid = <ChatAttachment>[];
    for (final attachment in attachments) {
      if (File(attachment.localPath).existsSync()) {
        valid.add(attachment);
      } else {
        _addLocalMessage('附件「${attachment.fileName}」文件已失效，请重新粘贴');
      }
    }
    if (valid.isEmpty && text.isEmpty) return;
    if (valid.isNotEmpty && text.isEmpty) {
      text = valid.every((a) => a.isImage) ? _defaultImagePrompt : _defaultAttachmentPrompt;
    }

    _conversation ??= ChatConversation(
      id: ChatStorageService.newConversationId(),
      title: text,
    );
    final conversationId = _conversation!.id;
    // 附件文件持久化到会话目录（重载缩略图展示与 /retry 依赖）
    await ChatAttachmentController.persistAll(conversationId, valid);
    // 构建历史消息（不含当前用户消息）
    final history = <Map<String, String>>[];
    for (final msg in _messages) {
      if (msg.text.isEmpty || msg.local) continue;
      history.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': _historyContent(msg),
      });
    }


    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true, attachments: valid));
      _isSending = true;
    });
    _saveConversation();
    _scrollToBottom(force: true);

    // 添加空的 AI 消息用于流式填充
    setState(() {
      _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
    });

    try {
      // 重置 agent 对话并传入历史，避免与旧 popup 状态冲突
      AgentService.resetConversation();
      await for (final event in AgentService.chatStream(
        text,
        mode: 'auto',
        history: history,
        conversationId: conversationId,
        attachments: valid,
      )) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case AgentRoundEvent():
              // 中间轮过程文字结束，插分隔线区分轮次
              if (_messages.last.text.trim().isNotEmpty || _messages.last.toolEvents.isNotEmpty) {
                _messages.last.streaming = false;
                _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
              }
            case AgentTokenEvent(:final text):
              _messages.last.text += text;
            case AgentQuestionEvent(:final questionId, :final questions):
              // 提问挂起：卡片显示在输入框上方，回答后经 _submitAgentAnswer 留痕
              if (questions.isNotEmpty) {
                setState(() {
                  _questionId = questionId;
                  _questionCtrl = AgentQuestionPanelController(questions: questions);
                });
              }
              case AgentToolEvent(:final id, :final name, :final running, :final error, :final details, :final changes):
              if (running) {
                // 工具调用属于新的执行轮次。若上一轮已经有文本，先切出独立气泡，
                // 避免工具返回的 diff 被渲染到最终回复的最底部。
                if (_messages.last.text.trim().isNotEmpty) {
                  _messages.last.streaming = false;
                  _messages.add(_ChatMessage(text: '', isUser: false, streaming: true));
                }
                _messages.last.toolEvents.add(_ToolEvent(
                  id,
                  name,
                  running: true,
                  parameters: details,
                ));
              } else {
                final index = _messages.last.toolEvents.lastIndexWhere(
                  (tool) => tool.id == id && tool.running,
                );
                if (index >= 0) {
                  final tool = _messages.last.toolEvents[index];
                  tool.running = false;
                  tool.error = error;
                  if (!error) tool.result = details;
                  if (error) tool.errorMessage = details?.toString();
                  if (!error && changes is List) {
                    for (final raw in changes.whereType<Map>()) {
                      final change = FileChangePreview.fromJson(Map<String, dynamic>.from(raw));
                      final existing = _messages.last.fileChanges.indexWhere((item) => item.path == change.path);
                      if (existing >= 0) _messages.last.fileChanges[existing] = change;
                      else _messages.last.fileChanges.add(change);
                      tool.changes.add(change);
                    }
                  }
                } else {
                  _messages.last.toolEvents.add(_ToolEvent(
                    id,
                    name,
                    running: false,
                    error: error,
                    parameters: details,
                    result: error ? null : details,
                    errorMessage: error ? details?.toString() : null,
                  ));
                }
              }
          }
        });
        _scrollToBottom();
      }
      if (mounted) {
        setState(() {
          _messages.last.streaming = false;
        });
      }
    } on AgentException catch (e) {
      if (!mounted) return;
      setState(() {
        final cancelled = e.message.toLowerCase().contains('cancel') ||
            e.message.toLowerCase().contains('abort');
        _messages.last.text = cancelled ? '已终止' : e.message;
        _messages.last.streaming = false;
        _messages.last.terminated = cancelled;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.last.text = '请求失败: $e';
        _messages.last.streaming = false;
        final message = e.toString().toLowerCase();
        if (message.contains('cancel') || message.contains('abort')) {
          _messages.last.text = '已终止';
          _messages.last.terminated = true;
        }
      });
    }

    if (mounted) {
      setState(() {
        _isSending = false;
        // 流已结束（完成/取消/断连）：收起未回答的提问卡片，questionId 已失效
        _dismissQuestionCard();
      });
    }
    _saveConversation();
    if (mounted && _queuedTexts.isNotEmpty) {
      final next = _queuedTexts.removeAt(0);
      await _sendText(next);
    }
  }

  /// 历史消息正文：用户消息的附件只留文件名引用（历史轮不重发附件内容，
  /// 避免每轮重复消耗视觉 token）；有文件改动时追加改动摘要（发回 LLM 用）
  String _historyContent(_ChatMessage msg) {
    var content = msg.text;
    if (msg.isUser && msg.attachments.isNotEmpty) {
      final refs = msg.attachments
          .map((a) => a.isImage ? '[图片: ${a.fileName}]' : '[附件: ${a.fileName}]')
          .join('\n');
      content = content.isEmpty ? refs : '$content\n$refs';
    }
    if (msg.isUser || msg.fileChanges.isEmpty) return content;
    final summary = msg.fileChanges.map((change) =>
        '[file change] ${change.operation}: ${change.path} (+${change.additions}/-${change.deletions})').join('\n');
    return '$content\n\n$summary';
  }

  /// 提交问题卡片答案：发送 user.answer → 气泡内留痕 → 收起卡片
  void _submitAgentAnswer() {
    final ctrl = _questionCtrl;
    if (ctrl == null || _questionId == null) return;
    _answerAgentQuestion(ctrl.questions, ctrl.answers, skipped: false);
  }

  /// 跳过当前提问：发送全空答案，LLM 侧视为未回答
  void _skipAgentQuestion() {
    final ctrl = _questionCtrl;
    if (ctrl == null || _questionId == null) return;
    _answerAgentQuestion(ctrl.questions, ctrl.skippedAnswers, skipped: true);
  }

  void _answerAgentQuestion(List<AgentQuestion> questions, List<List<String>> answers, {required bool skipped}) {
    final questionId = _questionId!;
    setState(() {
      _dismissQuestionCard();
      // 留痕挂在对应的 ask_user_question 工具行下面（与 FileChangesPanel 同级）：
      // user.question 一定发生在该工具 tool.start 之后、tool.result 之前
      final index = _messages.lastIndexWhere((m) => !m.isUser && m.toolEvents.any((t) => t.running && t.name == 'ask_user_question'));
      if (index >= 0) {
        final toolIndex = _messages[index].toolEvents.lastIndexWhere((t) => t.running && t.name == 'ask_user_question');
        _messages[index].toolEvents[toolIndex].questionPanels.add(_QuestionPanel(questions: questions, answers: answers, skipped: skipped));
      }
    });
    AgentService.answerQuestion(questionId, answers);
    _saveConversation();
  }

  /// 收起提问卡片（须在 setState 内调用）；卡片 controller 持有 text 输入框，需 dispose
  void _dismissQuestionCard() {
    _questionCtrl?.dispose();
    _questionCtrl = null;
    _questionId = null;
  }
}
