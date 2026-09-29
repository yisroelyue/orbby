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
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _messages.length,
              itemBuilder: (_, index) => _buildMessageBubble(_messages[index]),
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
    if (!_scrollController.hasClients) return;
    final show = _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels >
        50;
    if (show != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = show);
    }
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
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
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.sunken,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MessageStatusDot(
              status: MessageStatus.user,
              // 与下面用户正文同一行高，圆点才能落在首行中线上
              lineHeight: _userFontSize * _userLineHeightFactor,
            ),
            Expanded(
              child: Column(
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
                        letterSpacing: 0.1,
                        fontFamily: _fontFamily,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 工具行：单条直出；≥2 条折叠为步骤组（默认只显示概览，见 tool_steps.dart）
        if (msg.toolEvents.length == 1)
          _buildToolRow(msg.toolEvents.first)
        else if (msg.toolEvents.length > 1)
          _ToolStepsGroup(
            events: msg.toolEvents,
            expanded: msg.toolsExpanded,
            blinkOn: _toolBlinkOn,
            onToggle: () => setState(() => msg.toolsExpanded = !msg.toolsExpanded),
            rowBuilder: _buildToolRow,
            theme: theme,
          ),
        // 正文气泡：只在有文本或（等待占位且还没有工具行）时渲染。
        // fileChanges/diff 与问答卡都挂在工具行下，正文区只剩状态点时不渲染，
        // 否则会出现孤立圆点（工具行之间的 completed 绿点/processing 灰点）
        if (msg.text.trim().isNotEmpty || (msg.streaming && msg.toolEvents.isEmpty))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MessageStatusDot(
                  status: msg.terminated
                      ? MessageStatus.terminated
                      : msg.streaming
                          ? MessageStatus.processing
                          : MessageStatus.completed,
                  // 与 Markdown 段落同一行高（见 markdown.dart 的 p 样式）
                  lineHeight: _bodyFontSize * _bodyLineHeightFactor,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MarkdownBody(
                        data: msg.streaming ? '${msg.text}▌' : msg.text,
                        selectable: false,
                        builders: {
                          // 接管代码块（语言标签 + 复制按钮）与行内代码
                          // （灰底 chip）；样式取当前主题
                          'pre': _PreTextBuilder(theme: theme),
                          'code': _InlineCodeBuilder(theme: theme),
                        },
                        styleSheet: _markdownStyleSheet(),
                      ),
                    ],
                  ),
                ),
              ],
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
    return Padding(
      // 左缩进 38：工具块比正文（状态点轨）再退一档，弱化辅助信息（参考稿）
      padding: const EdgeInsets.fromLTRB(38, 2, 12, 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 工具图标（行首）：染 ink2 与标题同色；
        // top 按标题首行行高估算居中（12.5 × 默认行高 ≈1.4 ≈ 17.5 → (17.5-14)/2 ≈ 2）。
        // 无映射的工具不占位（行首直接是标题）。
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
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
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.ink2, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.2, fontFamily: _fontFamily),
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
    );
  }

  /// [view] 指定消息所属会话：仅当它是当前 tab 时才滚动（共享 scrollController，
  /// 后台会话流式增长不得拽动前台视图）；不传 = 当前会话（命令本地消息等）
  void _scrollToBottom({bool force = false, ChatSessionView? view}) {
    if (view != null && !identical(view, _current)) return;
    // 在当前帧提交前判断是否跟随，避免内容增长后 maxScrollExtent 变化导致
    // 原本在底部的用户被误判为“已滚动到前面”。
    final shouldFollow = force ||
        !_scrollController.hasClients ||
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50;
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
