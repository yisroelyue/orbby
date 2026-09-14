part of 'home_screen.dart';

/// 用户消息气泡内的附件缩略图（只读，点击看大图）
class _UserAttachmentThumb extends StatelessWidget {
  const _UserAttachmentThumb({required this.attachment, required this.onOpen});

  final ChatAttachment attachment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
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
            color: Colors.white54,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              attachment.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 9, fontFamily: 'Sarasa Mono SC'),
            ),
          ),
        ],
      );
    } else if (attachment.localPath.isNotEmpty && File(attachment.localPath).existsSync()) {
      body = Image.file(File(attachment.localPath), fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
              size: 16, color: Colors.white38));
    } else {
      body = const Icon(Icons.image_not_supported_outlined, size: 16, color: Colors.white38);
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
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            color: const Color(0xFF292929),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// 消息渲染：聊天列表、用户/Agent 气泡、工具调用行、文件变更面板、
/// 问答留痕卡、消息操作按钮，以及底部跟随滚动。
extension _HomeScreenMessages on _HomeScreenState {
  Widget _buildChatList() {
    return Theme(
      data: _listTheme,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _messages.length,
          itemBuilder: (_, index) {
            return _buildMessageBubble(_messages[index]);
          },
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    // step/turn 事件可能创建没有文本和内容的占位消息；完成后不应留下空白气泡。
    if (!msg.isUser &&
        !msg.streaming &&
        msg.text.trim().isEmpty &&
        msg.toolEvents.isEmpty &&
        msg.fileChanges.isEmpty) {
      return const SizedBox.shrink();
    }
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MessageStatusDot(status: MessageStatus.user),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 消息附件缩略图（重载会话后无内存缩略图，直接读本地文件）
                  if (msg.attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
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
                        color: _bubbleText,
                        fontSize: 13,
                        height: 1.4,
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
        for (final tool in msg.toolEvents)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedOpacity(opacity: tool.running ? (_toolBlinkOn ? 1 : 0.2) : 1, duration: const Duration(milliseconds: 180), child: Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: Icon(Icons.circle, size: 7, color: Colors.lightBlueAccent))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_toolDisplayName(tool.name), style: TextStyle(color: _bubbleText, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: _fontFamily)),
                // ask_user_question 的参数 dump 由问答留痕卡替代
                if (tool.name != 'ask_user_question' && (tool.parameters != null || tool.result != null || tool.errorMessage != null))
                  Text(_formatToolDetails(tool.name, tool.parameters, null, error: tool.errorMessage), maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: _fontFamily)),
                if (tool.errorMessage != null) Text(tool.errorMessage!, maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: _fontFamily)),
                if (tool.changes.isNotEmpty) FileChangesPanel(changes: tool.changes),
                // ask_user_question 的问答留痕卡（与 diff 面板同级）
                for (final panel in tool.questionPanels)
                  QuestionRecordCard(
                    questions: panel.questions,
                    answers: panel.answers,
                    skipped: panel.skipped,
                  ),
              ])),
            ]),
          ),
        // 正文气泡：只在有文本或（等待占位且还没有工具行）时渲染。
        // fileChanges/diff 与问答卡都挂在工具行下，正文区只剩状态点时不渲染，
        // 否则会出现孤立圆点（工具行之间的 completed 绿点/processing 灰点）
        if (msg.text.trim().isNotEmpty || (msg.streaming && msg.toolEvents.isEmpty))
          Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MessageStatusDot(
                status: msg.terminated
                    ? MessageStatus.terminated
                    : msg.streaming
                        ? MessageStatus.processing
                        : MessageStatus.completed,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MarkdownBody(
            data: msg.streaming ? '${msg.text}▌' : msg.text,
            selectable: false,
            builders: {
              // 只接管代码块文字颜色（含外边距与横向滚动）；背景/圆角/边框仍走样式表
              'pre': _PreTextBuilder(
                TextStyle(
                  color: _codeBlockText,
                  fontSize: 13,
                  fontFamily: _codeFont,
                  fontFamilyFallback: [_fontFamily],
                  ),
              ),
            },
            styleSheet: _markdownStyleSheet(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 临时隐藏：复制 / 重新生成按钮
        // if (!msg.streaming)
        //   Padding(
        //     padding: const EdgeInsets.only(left: 12, right: 12, top: 6),
        //     child: Row(
        //       children: [
        //         _buildActionButton('assets/svg/复制.svg', '复制', () {
        //           Clipboard.setData(ClipboardData(text: msg.text));
        //         }),
        //         const SizedBox(width: 14),
        //         _buildActionButton('assets/svg/重新.svg', '重新生成', () {
        //           // TODO: 重新生成
        //         }),
        //       ],
        //     ),
        //   ),
      ],
    );
  }

  Widget _buildActionButton(
      String svgAsset, String label, VoidCallback onTap) {
    final isHovered = _hoveredAction == label;
    final isSelected = _selectedAction == label;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredAction = label),
      onExit: (_) => setState(() => _hoveredAction = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedAction = label);
          onTap();
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) setState(() => _selectedAction = null);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected
                ? _chipActiveBg
                : isHovered
                    ? _chipActiveBg.withValues(alpha: 0.4)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SvgPicture.asset(
            svgAsset,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              isSelected || isHovered ? _chipActiveText : _statusText,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToBottom({bool force = false}) {
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
