import 'dart:io';

import 'package:flutter/material.dart';

import '../models/chat_attachment.dart';
import '../services/chat_attachment_controller.dart';
import 'chat_attachment_viewer.dart';

/// 输入框上方的附件缩略图条：读取中/失败/就绪三态 + 删除 + 点击看大图。
/// 配色与 CommandPalette 同系；状态全部来自 [ChatAttachmentController]，
/// 本组件只渲染，删除/查看动作回调宿主。
class ChatAttachmentPreview extends StatelessWidget {
  const ChatAttachmentPreview({
    super.key,
    required this.controller,
    this.onOpen,
  });

  final ChatAttachmentController controller;

  /// 点击缩略图打开大图；不传则用内置默认查看器
  final ValueChanged<ChatAttachment>? onOpen;

  static const _bg = Color(0xFF1E1E1E);
  static const _errorText = Color(0xFFEF9A9A);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        final error = controller.transientError;
        if (items.isEmpty && error == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    error,
                    style: const TextStyle(
                        color: _errorText, fontSize: 12, fontFamily: 'Sarasa Mono SC'),
                  ),
                ),
              if (items.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final item in items)
                        _AttachmentThumb(
                          attachment: item,
                          onRemove: () => controller.remove(item),
                          onOpen: () {
                            if (onOpen != null) {
                              onOpen!(item);
                            } else {
                              openAttachment(context, item);
                            }
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AttachmentThumb extends StatefulWidget {
  const _AttachmentThumb({
    required this.attachment,
    required this.onRemove,
    required this.onOpen,
  });

  final ChatAttachment attachment;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  State<_AttachmentThumb> createState() => _AttachmentThumbState();
}

class _AttachmentThumbState extends State<_AttachmentThumb> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.attachment.isReady ? widget.onOpen : null,
        child: Container(
          width: 76,
          height: 76,
          margin: const EdgeInsets.only(right: 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            color: const Color(0xFF292929),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBody(),
              // 删除角标：hover 显示
              AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: ColoredBox(
                  color: Colors.black45,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close, size: 18, color: Colors.white),
                    onPressed: widget.onRemove,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final attachment = widget.attachment;
    switch (attachment.status) {
      case ChatAttachmentStatus.loading:
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
          ),
        );
      case ChatAttachmentStatus.error:
        return const Center(
          child: Icon(Icons.broken_image_outlined, size: 22, color: Colors.white38),
        );
      case ChatAttachmentStatus.ready:
        // 图片优先用内存缩略图（重载会话后为空则回退文件解码）
        if (attachment.thumbnailBytes != null) {
          return Image.memory(attachment.thumbnailBytes!,
              fit: BoxFit.cover, gaplessPlayback: true);
        }
        if (attachment.isImage) {
          final file = File(attachment.localPath);
          if (file.existsSync()) {
            return Image.file(file, fit: BoxFit.cover, gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined, size: 22, color: Colors.white38));
          }
          return const Icon(Icons.image_not_supported_outlined,
              size: 22, color: Colors.white38);
        }
        // 非图片附件：类型图标 + 文件名 + 大小
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_iconForAttachment(attachment), size: 22, color: Colors.white54),
              const SizedBox(height: 4),
              Text(
                attachment.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 10, fontFamily: 'Sarasa Mono SC'),
              ),
              const SizedBox(height: 2),
              Text(
                _sizeLabel(attachment.sizeBytes),
                style: const TextStyle(color: Colors.white24, fontSize: 9),
              ),
            ],
          ),
        );
    }
  }

  static IconData _iconForAttachment(ChatAttachment attachment) =>
      attachment.mimeType == 'application/pdf'
          ? Icons.picture_as_pdf_outlined
          : Icons.text_snippet_outlined;

  static String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}
