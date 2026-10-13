part of 'home_screen.dart';

/// 用户消息气泡内的附件缩略图（只读，点击看大图）
class _UserAttachmentThumb extends StatelessWidget {
  const _UserAttachmentThumb({required this.attachment, required this.onOpen});

  final ChatAttachment attachment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    final thumbnail = attachment.thumbnailBytes;
    Widget body;
    if (thumbnail != null) {
      body = Image.memory(thumbnail, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (!attachment.isImage) {
      // 非图片附件：类型图标 + 文件名（点击调系统程序打开）
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            attachment.mimeType == 'application/pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.text_snippet_outlined,
            size: 18,
            color: theme.ink3,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              attachment.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.ink3, fontSize: 10, fontFamily: _fontFamily),
            ),
          ),
        ],
      );
    } else if (attachment.localPath.isNotEmpty && File(attachment.localPath).existsSync()) {
      body = Image.file(File(attachment.localPath), fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined,
              size: 16, color: theme.ink3));
    } else {
      body = Icon(Icons.image_not_supported_outlined, size: 16, color: theme.ink3);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.line),
            color: theme.sunken,
          ),
          child: body,
        ),
      ),
    );
  }
}

/// 消息渲染：聊天列表、用户/Agent 气泡、工具调用行、文件变更面板、
/// 问答留痕卡，以及底部跟随滚动。
extension _HomeScreenMessages on _HomeScreenState {
  Widget _buildChatList() {
    return Theme(
      data: _listThemes[_themeData.isDark]!,
      child: Stack(
        children: [
          SelectionArea(
            key: ObjectKey(_current),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message = _messages[index];
                // Keep each message's element and semantics subtree tied to
                // the message object when new bubbles are inserted or the
                // list is rebuilt during streaming/scrolling. Without a
                // stable boundary, Flutter may reuse neighboring semantics
                // nodes while their Markdown children are changing.
                return Semantics(
                  key: ObjectKey(message),
                  container: true,
                  explicitChildNodes: true,
                  child: _buildMessageBubble(
                    message,
                    previous: index > 0 ? _messages[index - 1] : null,
                    next: index < _messages.length - 1
                        ? _messages[index + 1]
                        : null,
                  ),
                );
              },
            ),
          ),
          if (_showScrollToBottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(
                child: _ScrollToBottomButton(onTap: () => _scrollToBottom(force: true)),
              ),
            ),
        ],
      ),
    );
  }

  void _onChatScroll() {
    final show = _scrollController.hasClients &&
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels >
        50;
    if (show != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = show);
    }
  }

  Widget _buildMessageBubble(_ChatMessage msg, {_ChatMessage? previous, _ChatMessage? next}) {
    final theme = _themeData;
    // step/turn 事件可能创建没有文本和内容的占位消息；完成后不应留下空白气泡。
    if (!msg.isUser &&
        !msg.streaming &&
        msg.text.trim().isEmpty &&
        msg.toolEvents.isEmpty &&
        msg.fileChanges.isEmpty) {
      return const SizedBox.shrink();
    }
    if (msg.isUser) {
      return LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
            // 对齐主界面参考稿：气泡后留出回答间距，右下角保留小收尾。
            margin: const EdgeInsets.only(top: 14, bottom: 32),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.userMessageBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                topRight: Radius.circular(13),
                bottomLeft: Radius.circular(13),
                bottomRight: Radius.circular(3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 消息附件缩略图（重载会话后无内存缩略图，直接读本地文件）
                      if (msg.attachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final attachment in msg.attachments)
                                _UserAttachmentThumb(
                                  attachment: attachment,
                                  onOpen: () => _viewAttachment(attachment),
                                ),
                            ],
                          ),
                        ),
                      if (msg.text.isNotEmpty)
                        Text(
                          msg.text,
                          style: TextStyle(
                            color: theme.ink,
                            fontSize: _userFontSize,
                            height: _userLineHeightFactor,
                            letterSpacing: 0,
                            fontFamily: _fontFamily,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ORBBY 标签（参考稿 .agent-label）：一次回答只显示一次。
        // 按消息序列推断——前一条是非 local 的 AI 泡（切轮/切泡产生的续泡）
        // 就归入同一次回答，不再重复打标签；不依赖落盘字段，历史会话同样正确。
        // 命令本地消息（local）不是 AI 回答，不打标签。
        if (!msg.local && !(previous != null && !previous.isUser && !previous.local))
          _AgentLabel(terminated: msg.terminated, theme: theme),
        // 工具行：单条直出；≥2 条折叠为步骤组（默认只显示概览，见 tool_steps.dart）
        if (msg.toolEvents.length == 1)
          _buildToolRow(msg.toolEvents.first)
        else if (msg.toolEvents.length > 1)
          _ToolStepsGroup(
            events: msg.toolEvents,
            expanded: msg.toolsExpanded,
            onToggle: () => setState(() => msg.toolsExpanded = !msg.toolsExpanded),
            rowBuilder: _buildToolRow,
            theme: theme,
          ),
        // 正文：只在有文本或（等待占位且还没有工具行）时渲染。
        // fileChanges/diff 与问答卡都挂在工具行下，正文区空时不渲染占位
        if (msg.text.trim().isNotEmpty || (msg.streaming && msg.toolEvents.isEmpty))
          Padding(
            // 工具提示后紧接正文；纯文本回答保留原有段落留白。
            // bottom 22 是「正文 → 用户下一个气泡」的消息收尾间距；回答没完
            // （下一条是同回答的续泡，判定与 ORBBY 标签推断对称）时收窄到 8，
            // 否则 22 + 续泡工具行顶部会在泡间凭空多出一行空白。
            padding: EdgeInsets.only(
              top: msg.toolEvents.isNotEmpty ? 6 : 12,
              bottom: next != null && !next.isUser && !next.local ? 8 : 22,
            ),
            child: msg.streaming
                ? _StreamingMarkdown(
                    data: msg.text,
                    styleSheet: _markdownStyleSheet(),
                    builders: {
                      'pre': _PreTextBuilder(theme: theme),
                      'code': _InlineCodeBuilder(theme: theme),
                    },
                  )
                : MarkdownBody(
              data: msg.text,
              selectable: false,
              builders: {
                // 接管代码块（语言标签 + 复制按钮）与行内代码
                // （灰底 chip）；样式取当前主题
                'pre': _PreTextBuilder(theme: theme),
                'code': _InlineCodeBuilder(theme: theme),
              },
              styleSheet: _markdownStyleSheet(),
            ),
          ),
      ],
    );
  }

  /// 单条工具调用行：直出与折叠组的展开详情共用同一实现
  Widget _buildToolRow(_ToolEvent tool) {
    final theme = _themeData;
    // 提问用户：挂起中（无留痕卡、无错误）整行不渲染，问答交互在输入框上方卡片；
    // 回答/跳过后渲染问答留痕卡
    if (tool.name == 'ask_user_question' && tool.questionPanels.isEmpty && tool.errorMessage == null) {
      return const SizedBox.shrink();
    }
    final icon = toolIconAsset(tool.name);
    // 提问用户行不画左边框竖线：标题已去掉、整行只承载问答留痕卡，
    // 竖线包着卡片视觉冗余；卡片直接与正文左对齐（其他工具行不变）
    final isAskRow = tool.name == 'ask_user_question';
    return Padding(
      // 与正文左对齐（无缩进），靠更小字号/更浅颜色弱化辅助信息。
      // ask 行顶部收窄：卡片无标题行，上方已有用户气泡的回答间距(32)，
      // 再叠常规标题行的 7 会显得空一大截
      padding: EdgeInsets.fromLTRB(0, isAskRow ? 2 : 7, 12, 0),
      child: Container(
        padding: EdgeInsets.only(left: isAskRow ? 0 : 12),
        decoration: isAskRow
            ? null
            : BoxDecoration(
                border: Border(
                  left: BorderSide(color: theme.line, width: 1),
                ),
              ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 工具图标（行首）：染 ink2 与标题同色；
        // top 按标题首行行高估算居中（11.5 × 默认行高 ≈1.4 ≈ 16 → (16-14)/2 ≈ 1）。
        // 无映射的工具不占位（行首直接是标题）。
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 6),
            child: SvgPicture.asset(
              icon,
              width: 14,
              height: 14,
              colorFilter: ColorFilter.mode(theme.ink2, BlendMode.srcIn),
            ),
          ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 标题与参数同一行（「读取文件：path: ...」），超宽软换行；
          // 错误不走详情（_formatToolDetails），只渲染下面独立错误行，防双写。
          // 提问用户不渲染标题：问答留痕卡已承载全部信息，行容器保留以挂载留痕卡
          if (tool.name != 'ask_user_question')
            Text.rich(
              _toolTitleSpan(tool),
              // 标题最多一行，超长 ellipsis（完整参数看展开详情/结果卡）
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 标题不加粗：Microsoft YaHei 只内嵌 400/700 两档，w600 实际渲染成 Bold
              style: TextStyle(color: theme.ink2, fontSize: 11.5, fontWeight: FontWeight.w400, letterSpacing: 0.2, fontFamily: _fontFamily),
            ),
          if (tool.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tool.errorMessage!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tool.errorMessage == '提问已搁置' ? theme.ink3 : theme.danger,
                  fontSize: 12,
                  fontFamily: _fontFamily,
                ),
              ),
            ),
          if (tool.changes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FileChangesPanel(changes: tool.changes),
            ),
          // ask_user_question 的问答留痕卡（与 diff 面板同级；标题已去掉，不留顶部间距）
          for (final panel in tool.questionPanels)
            QuestionRecordCard(
              questions: panel.questions,
              answers: panel.answers,
              skipped: panel.skipped,
            ),
        ])),
        ]),
      ),
    );
  }

  /// [view] 指定消息所属会话：仅当它是当前 tab 时才滚动（共享 scrollController，
  /// 后台会话流式增长不得拽动前台视图）；不传 = 当前会话（命令本地消息等）
  void _scrollToBottom({bool force = false, ChatSessionView? view}) {
    final targetView = view ?? _current;
    if (!mounted || !identical(targetView, _current)) return;
    // 在当前帧提交前判断是否跟随，避免内容增长后 maxScrollExtent 变化导致
    // 原本在底部的用户被误判为“已滚动到前面”。
    final shouldFollow = force ||
        !_scrollController.hasClients ||
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(targetView, _current)) return;
      if (_scrollController.hasClients && shouldFollow) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }
}

/// 流式回复末尾的细竖线光标。通过切换 Markdown 文本末尾字符，
/// 光标始终跟随最后一段文字，并避免使用实心方块字形。
class _StreamingMarkdown extends StatefulWidget {
  const _StreamingMarkdown({
    required this.data,
    required this.styleSheet,
    required this.builders,
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;

  @override
  State<_StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<_StreamingMarkdown> {
  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (mounted) setState(() => _visible = !_visible);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: '${widget.data}${_visible ? '│' : ''}',
      selectable: false,
      builders: widget.builders,
      styleSheet: widget.styleSheet,
    );
  }
}

/// AI 回答的行首标签（参考稿 .agent-label）：状态圆点 + ORBBY。
/// 一次回答只出现一次——续轮泡不打（见 _buildMessageBubble 的序列推断），
/// 命令本地消息不带；圆点颜色保留原状态点语义（完成绿 / 终止红）。
class _AgentLabel extends StatelessWidget {
  const _AgentLabel({required this.terminated, required this.theme});

  /// 回答被终止（Ctrl+C / 断连）时圆点转红
  final bool terminated;

  /// 宿主主题（消息渲染层直接读 State 字段，不经 context）
  final ChatThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: terminated ? theme.term : theme.done,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'ORBBY',
            style: TextStyle(
              color: theme.ink,
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 1,
              height: 1,
              fontFamily: _fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

/// 回到底部浮钮（参考稿 .jump）：32px 描边白卡圆钮 + 浮层阴影
class _ScrollToBottomButton extends StatefulWidget {
  const _ScrollToBottomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ScrollToBottomButton> createState() => _ScrollToBottomButtonState();
}

class _ScrollToBottomButtonState extends State<_ScrollToBottomButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: '滚动到底部',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.raised,
              shape: BoxShape.circle,
              border: Border.all(color: theme.line),
              boxShadow: theme.popShadows,
            ),
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: _hovered ? theme.ink : theme.ink2,
            ),
          ),
        ),
      ),
    );
  }
}
