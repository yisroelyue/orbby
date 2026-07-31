import 'package:flutter/material.dart';

import '../models/json_node.dart';
import 'json_node_tile.dart';

/// 递归渲染 JSON 树，支持节点折叠/展开和全部展开/折叠。
class JsonTreeView extends StatefulWidget {
  const JsonTreeView({super.key, required this.rootNode});

  final JsonNode rootNode;

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonTreeViewState extends State<JsonTreeView> {
  /// 将可见节点（考虑折叠状态）扁平化为一列。
  List<JsonNode> _flatten(JsonNode node) {
    final result = <JsonNode>[node];
    if (node.isExpanded && node.children != null) {
      for (final child in node.children!) {
        result.addAll(_flatten(child));
      }
    }
    return result;
  }

  void _toggle(JsonNode node) {
    setState(() => node.isExpanded = !node.isExpanded);
  }

  void _setAllExpanded(JsonNode node, bool expanded) {
    node.isExpanded = expanded;
    for (final child in node.children ?? const <JsonNode>[]) {
      _setAllExpanded(child, expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _flatten(widget.rootNode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              primary: true,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final node in nodes)
                    JsonNodeTile(node: node, onToggle: () => _toggle(node)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _setAllExpanded(widget.rootNode, true)),
            icon: const Icon(Icons.unfold_more, size: 15),
            label: const Text('全部展开', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () => setState(() => _setAllExpanded(widget.rootNode, false)),
            icon: const Icon(Icons.unfold_less, size: 15),
            label: const Text('全部折叠', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
