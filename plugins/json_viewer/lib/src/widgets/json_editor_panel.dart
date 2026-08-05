import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 左侧原始报文编辑面板：工具栏 + 可编辑文本框。
class JsonEditorPanel extends StatelessWidget {
  const JsonEditorPanel({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.pathController,
    this.onOpenFile,
    this.onSaveFile,
    this.onFormat,
    this.onCompress,
    this.onCopy,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final TextEditingController pathController;
  final VoidCallback? onOpenFile;
  final VoidCallback? onSaveFile;
  final VoidCallback? onFormat;
  final VoidCallback? onCompress;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyS, control: true): () => onSaveFile?.call(),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 13,
                fontFamily: 'Consolas',
                height: 1.5,
              ),
              cursorColor: Colors.white54,
              keyboardAppearance: Brightness.dark,
              decoration: InputDecoration(
                hintText: '在此粘贴或输入 JSON 报文…',
                hintStyle: const TextStyle(
                  color: Colors.white24,
                  fontSize: 13,
                  fontFamily: 'Consolas',
                ),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                contentPadding: const EdgeInsets.all(12),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: pathController,
                onSubmitted: (_) => onOpenFile?.call(),
                style: const TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 12,
                  fontFamily: 'Consolas',
                ),
                decoration: InputDecoration(
                  hintText: '文件路径，不输入则使用文件选择器。',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _toolBtn(Icons.folder_open, '打开文件', onOpenFile),
          const SizedBox(width: 6),
          _toolBtn(Icons.save, '保存 (Ctrl+S)', onSaveFile),
          const SizedBox(width: 6),
          _toolBtn(Icons.unfold_more, '展开', onFormat),
          const SizedBox(width: 6),
          _toolBtn(Icons.compress, '压缩', onCompress),
          const Spacer(),
          _toolBtn(Icons.copy, '复制到剪贴板', onCopy),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback? onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 17, color: Colors.white70),
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
