import 'dart:io';

import 'package:flutter/material.dart';

import '../models/chat_attachment.dart';

/// 附件查看统一入口：图片走应用内大图查看器；文本/PDF 调系统默认程序打开
/// （不做应用内渲染），文件失效或打开失败时弹层提示。
Future<void> openAttachment(BuildContext context, ChatAttachment attachment) async {
  if (attachment.isImage) return showAttachmentViewer(context, attachment);
  final file = File(attachment.localPath);
  if (!file.existsSync()) {
    _showMissingDialog(context, attachment);
    return;
  }
  try {
    // explorer.exe <文件> = 用系统默认关联程序打开
    await Process.run('explorer.exe', [file.absolute.path]);
  } catch (_) {
    if (context.mounted) _showMissingDialog(context, attachment);
  }
}

void _showMissingDialog(BuildContext context, ChatAttachment attachment) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text('文件「${attachment.fileName}」不存在或无法打开，可能已被清理，请重新粘贴'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 附件大图查看器：模态弹层，点击背景关闭，支持缩放拖拽。
/// 文件已失效时给出明确提示（提示重新粘贴）。
Future<void> showAttachmentViewer(BuildContext context, ChatAttachment attachment) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => GestureDetector(
      onTap: () => Navigator.pop(dialogContext),
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: GestureDetector(
          // 拦截图片区域的点击，避免拖拽缩放时误关
          onTap: () {},
          child: InteractiveViewer(
            maxScale: 6,
            child: _ViewerImage(attachment: attachment),
          ),
        ),
      ),
    ),
  );
}

class _ViewerImage extends StatelessWidget {
  const _ViewerImage({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final file = File(attachment.localPath);
    if (!file.existsSync()) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.white38),
          const SizedBox(height: 12),
          Text(
            '图片「${attachment.fileName}」文件不存在，可能已被清理，请重新粘贴',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
          ),
        ],
      );
    }
    return Image.file(
      file,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38),
          const SizedBox(height: 12),
          Text(
            '图片「${attachment.fileName}」读取失败',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
