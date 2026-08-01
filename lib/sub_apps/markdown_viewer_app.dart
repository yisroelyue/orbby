import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:orbby/core/sub_app.dart';
import 'package:orbby/core/sub_app_registry.dart';
import 'package:window_manager/window_manager.dart';

class MarkdownViewerApp extends SubApp {
  @override
  String get id => 'markdown_viewer';

  @override
  String get name => 'Markdown 查看器';

  @override
  String get description => '编辑原始报文，实时预览 Markdown 渲染效果';

  @override
  String get iconAsset => 'assets/svg/markdown.svg';

  @override
  String get packageName => 'orbby';

  @override
  Size get preferredWindowSize => const Size(1200, 1000);

  @override
  bool get showWindowTitleBar => false;

  @override
  Widget buildApp(BuildContext context) {
    return const _MarkdownViewerContent();
  }
}

// ─── 颜色常量 ───────────────────────────────────────────────────────────────

const _bg = Color(0xFF1E1E1E);
const _panelBg = Color(0xFF252525);
const _border = Color(0xFF333333);
const _textPrimary = Color(0xFFE0E0E0);
const _textSecondary = Color(0xFF9E9E9E);
const _accent = Color(0xFF448AFF);
const _dividerColor = Color(0xFF3A3A3A);

// ─── 主内容组件 ─────────────────────────────────────────────────────────────

class _MarkdownViewerContent extends StatefulWidget {
  const _MarkdownViewerContent();

  @override
  State<_MarkdownViewerContent> createState() => _MarkdownViewerContentState();
}

class _MarkdownViewerContentState extends State<_MarkdownViewerContent> {
  final _textController = TextEditingController();
  final _previewScrollController = ScrollController();

  double _dividerPosition = 0.5;
  bool _isDragging = false;
  bool _isMaximized = false;
  String? _currentFilePath;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  String get _rawMarkdown => _textController.text;

  // ── 文件操作 ───────────────────────────────────────────────────────────

  Future<void> _openFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    try {
      final content = await File(filePath).readAsString();
      _textController.text = content;
      _currentFilePath = filePath;
      if (mounted) {
        _showSnackBar('已加载: ${result.files.first.name}');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('读取文件失败: $e', error: true);
      }
    }
  }

  void _showSnackBar(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: error ? Colors.red.shade800 : const Color(0xFF333333),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        colorSchemeSeed: _accent,
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
      ),
      child: Column(
        children: [
          _buildTitleBar(),
          _buildToolbar(),
          Expanded(child: _buildSplitView()),
        ],
      ),
    );
  }

  // ── 标题栏 ─────────────────────────────────────────────────────────────

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: _panelBg,
          border: Border(bottom: BorderSide(color: _border, width: 0.5)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(Icons.article_outlined, size: 18, color: _accent),
            const SizedBox(width: 8),
            const Text('Markdown 查看器',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none)),
            if (_currentFilePath != null) ...[
              const SizedBox(width: 8),
              Text(_currentFilePath!.split(Platform.pathSeparator).last,
                  style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 11,
                      decoration: TextDecoration.none)),
            ],
            const Spacer(),
            _TitleBarBtn(
                icon: Icons.minimize_rounded,
                onTap: () => windowManager.minimize()),
            const SizedBox(width: 4),
            _TitleBarBtn(
                icon: _isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                onTap: () {
                  if (_isMaximized) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                  setState(() => _isMaximized = !_isMaximized);
                }),
            const SizedBox(width: 4),
            _TitleBarBtn(
                icon: Icons.close_rounded, onTap: () => windowManager.hide()),
          ],
        ),
      ),
    );
  }

  // ── 工具栏 ─────────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _panelBg,
        border: Border(bottom: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(
        children: [
          _ToolBtn(
            icon: Icons.folder_open_rounded,
            label: '打开文件',
            onTap: _openFile,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ── 分割视图 ───────────────────────────────────────────────────────────

  Widget _buildSplitView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final dividerWidth = 4.0;
        final leftWidth = (totalWidth - dividerWidth) * _dividerPosition;
        final rightWidth = totalWidth - leftWidth - dividerWidth;

        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: leftWidth,
              child: _buildEditorPanel(),
            ),
            Positioned(
              left: leftWidth,
              top: 0,
              bottom: 0,
              width: dividerWidth,
              child: _buildDivider(),
            ),
            Positioned(
              left: leftWidth + dividerWidth,
              top: 0,
              bottom: 0,
              right: 0,
              child: _buildPreviewPanel(),
            ),
          ],
        );
      },
    );
  }

  // ── 左侧编辑面板 ───────────────────────────────────────────────────────

  Widget _buildEditorPanel() {
    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border, width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontFamily: 'Cascadia Code, Consolas, monospace',
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    hintText: '在此输入 Markdown 内容...',
                    hintStyle: TextStyle(color: _textSecondary, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              '${_rawMarkdown.length} 字符 | ${_rawMarkdown.split('\n').length} 行',
              style: const TextStyle(fontSize: 11, color: _textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── 分割线 ─────────────────────────────────────────────────────────────

  Widget _buildDivider() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) => _isDragging = true,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _dividerPosition += details.delta.dx / (context.size?.width ?? 1);
            _dividerPosition = _dividerPosition.clamp(0.2, 0.8);
          });
        },
        onHorizontalDragEnd: (_) => _isDragging = false,
        child: Container(
          color: _isDragging ? _accent : _dividerColor,
          child: Center(
            child: Container(
              width: 2,
              height: 32,
              decoration: BoxDecoration(
                color: _isDragging
                    ? Colors.white38
                    : _textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 右侧预览面板 ───────────────────────────────────────────────────────

  Widget _buildPreviewPanel() {
    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border, width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: _rawMarkdown.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article_outlined,
                                size: 40, color: _textSecondary.withValues(alpha: 0.3)),
                            const SizedBox(height: 10),
                            const Text('在左侧输入 Markdown 开始预览',
                                style: TextStyle(
                                    fontSize: 13, color: _textSecondary)),
                          ],
                        ),
                      )
                    : SelectionArea(
                        child: Markdown(
                          data: _rawMarkdown,
                          selectable: false,
                          controller: _previewScrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          styleSheet: MarkdownStyleSheet(
                            h1: const TextStyle(
                                color: _textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                height: 2.2),
                            h2: const TextStyle(
                                color: _textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                height: 2.0),
                            h3: const TextStyle(
                                color: _textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                height: 1.8),
                            h4: const TextStyle(
                                color: _textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.6),
                            p: const TextStyle(
                                color: _textPrimary, fontSize: 14, height: 1.7),
                            code: const TextStyle(
                                color: Color(0xFF81C784),
                                fontSize: 13,
                                fontFamily: 'Cascadia Code, Consolas, monospace'),
                          codeblockDecoration: BoxDecoration(
                            color: const Color(0xFF151515),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _border, width: 0.5),
                          ),
                          blockquote: const TextStyle(
                              color: _textSecondary,
                              fontSize: 14,
                              height: 1.6),
                          blockquoteDecoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(4),
                            border: Border(
                              left: BorderSide(
                                  color: _accent.withValues(alpha: 0.5),
                                  width: 3),
                            ),
                          ),
                          tableBorder:
                              TableBorder.all(color: _border, width: 0.5),
                          tableHead: const TextStyle(
                              color: _textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          tableBody: const TextStyle(
                              color: _textPrimary, fontSize: 13),
                          tableHeadAlign: TextAlign.center,
                          tableCellsDecoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                          ),
                          tableColumnWidth: const FlexColumnWidth(),
                          listBullet: const TextStyle(
                              color: _accent, fontSize: 14),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                  color: _dividerColor, width: 0.5),
                            ),
                          ),
                          strong: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w700),
                          em: const TextStyle(
                              color: _textPrimary,
                              fontStyle: FontStyle.italic),
                          del: const TextStyle(
                              color: _textSecondary,
                              decoration: TextDecoration.lineThrough),
                          a: const TextStyle(
                              color: _accent,
                              decoration: TextDecoration.underline),
                          checkbox: const TextStyle(
                              color: _accent, fontSize: 14),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 标题栏按钮 ─────────────────────────────────────────────────────────────

class _TitleBarBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TitleBarBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white60, size: 16),
      ),
    );
  }
}

// ─── 工具栏按钮 ─────────────────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: _accent),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _accent)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 注册 ───────────────────────────────────────────────────────────────────

void registerMarkdownViewerApp() {
  SubAppRegistry.register(() => MarkdownViewerApp());
}
