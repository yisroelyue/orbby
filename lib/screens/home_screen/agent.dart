part of 'home_screen.dart';

/// Agent 链路：消息发送入口、核心发送流程（chatStream 消费）、
/// /compact 上下文压缩、提问卡片的提交/跳过/收起。
extension _HomeScreenAgent on _HomeScreenState {
  /// /compact：压缩上下文；摘要只写入 Agent 上下文，不展示摘要正文
  Future<void> _runCompact() async {
    if (!mounted || _isSending) return;
    if (_messages.isEmpty) {
      _addLocalMessage('当前没有对话可压缩。');
      return;
    }
    setState(() {
      _isSending = true;
    });
    _addLocalMessage('正在压缩上下文…');
    try {
      await AgentService.compact(sessionId: _current.agentSessionId);
      if (mounted) _addLocalMessage('上下文已压缩');
    } catch (e) {
      if (!mounted) return;
      _messages.add(_ChatMessage(text: '压缩失败: $e', isUser: false));
      setState(() => _messages.last.text = '压缩失败: $e');
    }
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
    _focusInput();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    // 输入为空且无附件不发送；有附件时允许说明为空（用默认文案）
    if (text.isEmpty && _attachmentCtrl.isEmpty) return;

    if (text.startsWith('/')) {
      _addInputHistory(text);
      // prepareInput 命令带参形态 `/命令名 参数`：剥前缀后交命令的带参入口
      // （勿在此硬编码判断具体命令名，统一走 _matchPrepareCommand 分派）
      final prepared = _matchPrepareCommand(text);
      if (prepared != null) {
        _inputController.clear();
        await prepared.$1.executeWithArgument?.call(prepared.$2);
        return;
      }
      // '/' 开头按命令处理：精确匹配则按 behavior 分派，否则丢弃（不把命令残片发给 AI）
      final cmd = _palette.findExact(text.substring(1));
      _inputController.clear();
      if (cmd != null) {
        if (cmd.behavior == ChatCommandBehavior.prepareInput) {
          // 直接发送纯命令名（trim 后无尾随空格）：以空参数执行（如 /cd 查看当前工作区）。
          // 准备态只保留给面板确认路径（/命令名 写回输入框等补参数），否则会死循环。
          final withArgument = cmd.executeWithArgument;
          if (withArgument != null) {
            await withArgument('');
          } else {
            _prepareInputCommand(cmd);
          }
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
      setState(() {
        _messages.add(_ChatMessage(text: '->next task: $text', isUser: true, pending: true));
      });
      setState(() => _queuedTexts.add(text));
      _scrollToBottom(force: true);
      return;
    }
    await _sendText(text);
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

  /// 核心发送流程：追加用户消息并流式请求回复（输入发送与 /retry 共用）。
  /// [target] 指定目标会话（队列续发必须传原会话）；默认当前 tab。
  /// 全程持 view 引用读写——流式期间用户可能切走 tab，经 `_current`
  /// 间接访问会把内容串进前台会话。
  Future<void> _sendText(String text, {List<ChatAttachment> attachments = const [], ChatSessionView? target}) async {
    final view = target ?? _current;
    if (view.isSending) {
      setState(() {
        view.messages.add(_ChatMessage(text: '->next task: $text', isUser: true, pending: true));
      });
      view.queuedTexts.add(text);
      _scrollToBottom(force: true, view: view);
      return;
    }

    final pendingIndex = view.messages.indexWhere((m) => m.isUser && m.pending && (m.text == text || m.text == '->next task: $text'));
    final reusedPendingMessage = pendingIndex >= 0;
    if (pendingIndex >= 0) {
      view.messages[pendingIndex].text = text;
      view.messages[pendingIndex].pending = false;
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

    view.conversation ??= ChatConversation(
      id: ChatStorageService.newConversationId(),
      title: text,
    );
    final conversationId = view.conversation!.id;
    // 附件文件持久化到会话目录（重载缩略图展示与 /retry 依赖）
    await ChatAttachmentController.persistAll(conversationId, valid);
    // 构建历史消息（不含当前用户消息）
    final history = <Map<String, String>>[];
    for (final msg in view.messages) {
      if (msg.text.isEmpty || msg.local || msg.pending) continue;
      history.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': _historyContent(msg),
      });
    }


    setState(() {
      if (!reusedPendingMessage) {
        view.messages.add(_ChatMessage(text: text, isUser: true, attachments: valid));
      } else if (valid.isNotEmpty) {
        view.messages[pendingIndex].attachments.addAll(valid);
      }
      view.isSending = true;
    });
    _saveConversation(view);
    _scrollToBottom(force: true, view: view);

    // 添加空的 AI 消息用于流式填充；持有引用而非依赖 view.messages.last——
    // 流式期间用户排队新任务会在末尾插入 next task 气泡，messages.last 会错位
    // 把 AI 回复拼进排队消息。切轮次/切泡时同步更新引用。
    var reply = _ChatMessage(text: '', isUser: false, streaming: true);
    setState(() {
      view.messages.add(reply);
    });

    try {
      // 重置该会话的 agent 对话并传入历史，避免与旧上下文冲突
      AgentService.resetConversation(sessionId: view.agentSessionId);
      await for (final event in AgentService.chatStream(
        text,
        mode: 'auto',
        history: history,
        conversationId: conversationId,
        attachments: valid,
        sessionId: view.agentSessionId,
      )) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case AgentRoundEvent():
              // 中间轮过程文字结束才切泡；纯工具轮不切（与下方 tool.running 分支
              // 的切泡条件一致），连续工具调用留在同一气泡内，≥2 条折叠为步骤组
              if (reply.text.trim().isNotEmpty) {
                reply.streaming = false;
                reply = _ChatMessage(text: '', isUser: false, streaming: true);
                view.messages.add(reply);
              }
            case AgentTokenEvent(:final text):
              reply.text += text;
            case AgentQuestionEvent(:final questionId, :final questions):
              // 提问挂起：卡片显示在输入框上方，回答后经 _submitAgentAnswer 留痕。
              // 写入目标会话（view）；后台会话挂起提问时卡片不可见，tab 上以红点提醒
              if (questions.isNotEmpty) {
                view.questionId = questionId;
                view.questionCtrl = AgentQuestionPanelController(questions: questions);
              }
              case AgentToolEvent(:final id, :final name, :final running, :final error, :final details, :final changes):
              if (running) {
                // 工具调用属于新的执行轮次。若上一轮已经有文本，先切出独立气泡，
                // 避免工具返回的 diff 被渲染到最终回复的最底部。
                if (reply.text.trim().isNotEmpty) {
                  reply.streaming = false;
                  reply = _ChatMessage(text: '', isUser: false, streaming: true);
                  view.messages.add(reply);
                }
                reply.toolEvents.add(_ToolEvent(
                  id,
                  name,
                  running: true,
                  parameters: details,
                ));
              } else {
                final index = reply.toolEvents.lastIndexWhere(
                  (tool) => tool.id == id && tool.running,
                );
                if (index >= 0) {
                  final tool = reply.toolEvents[index];
                  final cancelledQuestion = error &&
                      details?.toString().toLowerCase().contains('question cancelled') == true;
                  tool.running = false;
                  tool.error = error;
                  if (!error) tool.result = details;
                  if (error) tool.errorMessage = cancelledQuestion ? '提问已搁置' : details?.toString();
                  if (!error && changes is List) {
                    for (final raw in changes.whereType<Map>()) {
                      final change = FileChangePreview.fromJson(Map<String, dynamic>.from(raw));
                      final existing = reply.fileChanges.indexWhere((item) => item.path == change.path);
                      if (existing >= 0) reply.fileChanges[existing] = change;
                      else reply.fileChanges.add(change);
                      tool.changes.add(change);
                    }
                  }
                } else {
                  reply.toolEvents.add(_ToolEvent(
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
        _scrollToBottom(view: view);
      }
      if (mounted) {
        setState(() {
          reply.streaming = false;
        });
      }
    } on AgentException catch (e) {
      if (!mounted) return;
      setState(() {
        final cancelled = e.message.toLowerCase().contains('cancel') ||
            e.message.toLowerCase().contains('abort');
        reply.text = cancelled ? '已终止' : e.message;
        reply.streaming = false;
        reply.terminated = cancelled;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        reply.text = '请求失败: $e';
        reply.streaming = false;
        final message = e.toString().toLowerCase();
        if (message.contains('cancel') || message.contains('abort')) {
          reply.text = '已终止';
          reply.terminated = true;
        }
      });
    }

    if (mounted) {
      setState(() {
        view.isSending = false;
        // 流已结束（完成/取消/断连）：收起该会话未回答的提问卡片，questionId 已失效
        _dismissQuestionCard(view);
      });
    }
    _saveConversation(view);
    if (mounted && view.queuedTexts.isNotEmpty) {
      final next = view.queuedTexts.removeAt(0);
      await _sendText(next, target: view);
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

  /// Esc 退出提问：取消当前 Agent 请求，不向挂起的工具发送空答案。
  void _cancelAgentQuestion() {
    if (_questionCtrl == null || _questionId == null) return;
    AgentService.cancelCurrent(sessionId: _current.agentSessionId);
    setState(_dismissQuestionCard);
  }

  void _answerAgentQuestion(List<AgentQuestion> questions, List<List<String>> answers, {required bool skipped}) {
    // 提问卡片只在当前 tab 显示/提交，读写 _current 是安全的
    final view = _current;
    final questionId = view.questionId!;
    setState(() {
      _dismissQuestionCard();
      // 留痕挂在对应的 ask_user_question 工具行下面（与 FileChangesPanel 同级）：
      // user.question 一定发生在该工具 tool.start 之后、tool.result 之前
      final index = view.messages.lastIndexWhere((m) => !m.isUser && m.toolEvents.any((t) => t.running && t.name == 'ask_user_question'));
      if (index >= 0) {
        final toolIndex = view.messages[index].toolEvents.lastIndexWhere((t) => t.running && t.name == 'ask_user_question');
        view.messages[index].toolEvents[toolIndex].questionPanels.add(_QuestionPanel(questions: questions, answers: answers, skipped: skipped));
      }
    });
    AgentService.answerQuestion(questionId, answers, sessionId: view.agentSessionId);
    _saveConversation();
  }

  /// 收起提问卡片（须在 setState 内调用）；卡片 controller 持有 text 输入框，需 dispose。
  /// [view] 不传 = 当前 tab；流式收尾时传目标会话（可能已不在前台）
  void _dismissQuestionCard([ChatSessionView? view]) {
    final target = view ?? _current;
    target.questionCtrl?.dispose();
    target.questionCtrl = null;
    target.questionId = null;
  }
}
