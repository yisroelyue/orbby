import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/json_node.dart';
import 'widgets/json_editor_panel.dart';
import 'widgets/json_tree_view.dart';

/// JSON 数据查看器主界面：左右双栏，左侧原始报文，右侧树结构预览。
class JsonViewerScreen extends StatefulWidget {
  const JsonViewerScreen({super.key});

  @override
  State<JsonViewerScreen> createState() => _JsonViewerScreenState();
}

class _JsonViewerScreenState extends State<JsonViewerScreen> {
  final _textController = TextEditingController();
  JsonNode? _rootNode;
  String? _parseError;
  Timer? _debounceTimer;
  double _leftRatio = 0.45;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  // ── JSON 解析 ────────────────────────────────────────────────

  void _onTextChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _parseJson(text);
    });
  }

  void _parseJson(String text) {
    if (text.trim().isEmpty) {
      setState(() {
        _rootNode = null;
        _parseError = null;
      });
      return;
    }
    try {
      final parsed = jsonDecode(text);
      setState(() {
        _rootNode = JsonNode.fromValue(parsed);
        _parseError = null;
      });
    } catch (e) {
      setState(() {
        _rootNode = null;
        _parseError = e.toString();
      });
    }
  }

  // ── 工具栏操作 ──────────────────────────────────────────────

  void _formatJson() {
    try {
      final parsed = jsonDecode(_textController.text);
      final formatted = const JsonEncoder.withIndent('  ').convert(parsed);
      _applyText(formatted);
    } catch (_) {
      // JSON 无效时不操作
    }
  }

  void _compressJson() {
    try {
      final parsed = jsonDecode(_textController.text);
      final compressed = const JsonEncoder().convert(parsed);
      _applyText(compressed);
    } catch (_) {
      // JSON 无效时不操作
    }
  }

  void _applyText(String text) {
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    _parseJson(text);
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _textController.text));
  }

  Future<void> _openFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      if (!mounted) return;
      _applyText(content);
    } catch (_) {
      // 读取失败时忽略
    }
  }

  // ── 界面构建 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final leftWidth = constraints.maxWidth * _leftRatio;
          return Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPanelHeader('原始报文'),
                    Expanded(
                      child: JsonEditorPanel(
                        controller: _textController,
                        onChanged: _onTextChanged,
                        onOpenFile: _openFile,
                        onFormat: _formatJson,
                        onCompress: _compressJson,
                        onCopy: _copyToClipboard,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDivider(),
              Expanded(child: _buildRightPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDivider() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        final totalWidth = context.size?.width ?? 960;
        setState(() {
          _leftRatio += details.delta.dx / totalWidth;
          _leftRatio = _leftRatio.clamp(0.25, 0.7);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: const Color(0xFF333333),
        ),
      ),
    );
  }

  Widget _buildPanelHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF252525),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (title == '树结构预览' && _rootNode != null)
            Text(
              '${_countNodes(_rootNode!)} 节点',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
    );
  }

  int _countNodes(JsonNode node) {
    var count = 1;
    for (final child in node.children ?? const <JsonNode>[]) {
      count += _countNodes(child);
    }
    return count;
  }

  Widget _buildRightPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPanelHeader('树结构预览'),
        Expanded(child: _buildTreeArea()),
      ],
    );
  }

  Widget _buildTreeArea() {
    if (_parseError != null) return _buildErrorCard(_parseError!);
    if (_rootNode != null) {
      return JsonTreeView(
        key: ValueKey(_rootNode),
        rootNode: _rootNode!,
      );
    }
    return _buildEmptyState();
  }

  Widget _buildErrorCard(String error) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'JSON 解析错误',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            error,
            style: const TextStyle(
              color: Color(0xFFEF9A9A),
              fontSize: 12,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon(Icons.account_tree_outlined, size: 40, color: Colors.white24),
          // const SizedBox(height: 12),
          Text(
            '在左侧输入 JSON 后，此处将显示树结构',
            style: TextStyle(color: Colors.white30, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
