import 'package:flutter/material.dart';

import '../models/json_node.dart';

/// 单个 JSON 树节点的行组件。
class JsonNodeTile extends StatelessWidget {
  const JsonNodeTile({
    super.key,
    required this.node,
    required this.onToggle,
  });

  final JsonNode node;
  final VoidCallback onToggle;

  // JSON 类型配色
  static const _stringColor = Color(0xFF81C784); // 绿
  static const _numberColor = Color(0xFF64B5F6); // 蓝
  static const _boolColor = Color(0xFFFFB74D); // 橙
  static const _nullColor = Color(0xFF9E9E9E); // 灰
  static const _keyColor = Color(0xFFCE93D8); // 紫
  static const _containerColor = Color(0xFF9E9E9E); // 灰

  /// 节点类型对应的图标。
  static IconData _iconFor(JsonNodeType type) {
    switch (type) {
      case JsonNodeType.object:
        return Icons.data_object;
      case JsonNodeType.array:
        return Icons.data_array;
      case JsonNodeType.string_:
        return Icons.text_fields;
      case JsonNodeType.number_:
        return Icons.tag;
      case JsonNodeType.boolean_:
        return Icons.toggle_on;
      case JsonNodeType.null_:
        return Icons.block;
    }
  }

  /// 节点类型对应的颜色。
  static Color _colorFor(JsonNodeType type) {
    switch (type) {
      case JsonNodeType.object:
        return _boolColor;
      case JsonNodeType.array:
        return _numberColor;
      case JsonNodeType.string_:
        return _stringColor;
      case JsonNodeType.number_:
        return _numberColor;
      case JsonNodeType.boolean_:
        return _boolColor;
      case JsonNodeType.null_:
        return _nullColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isContainer = node.isContainer;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isContainer ? onToggle : null,
        child: Container(
          padding: EdgeInsets.only(
            left: node.depth * 20.0,
            right: 8,
            top: 2,
            bottom: 2,
          ),
          color: Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: isContainer
                    ? Icon(
                        node.isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 18,
                        color: Colors.white54,
                      )
                    : null,
              ),
              const SizedBox(width: 2),
              Icon(
                _iconFor(node.type),
                size: 15,
                color: _colorFor(node.type),
              ),
              const SizedBox(width: 6),
              if (node.key != null) ...[
                Text(
                  node.key!,
                  style: const TextStyle(
                    color: _keyColor,
                    fontSize: 13,
                    fontFamily: 'Consolas',
                  ),
                ),
                const Text(
                  ': ',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
              Expanded(
                child: _buildValue(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValue() {
    switch (node.type) {
      case JsonNodeType.string_:
        return Text(
          '"${node.displayValue}"',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _stringColor, fontSize: 13, fontFamily: 'Consolas'),
        );
      case JsonNodeType.number_:
        return Text(
          node.displayValue,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _numberColor, fontSize: 13, fontFamily: 'Consolas'),
        );
      case JsonNodeType.boolean_:
        return Text(
          node.displayValue,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _boolColor, fontSize: 13, fontFamily: 'Consolas'),
        );
      case JsonNodeType.null_:
        return Text(
          node.displayValue,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _nullColor,
            fontSize: 13,
            fontFamily: 'Consolas',
            fontStyle: FontStyle.italic,
          ),
        );
      case JsonNodeType.object:
      case JsonNodeType.array:
        return Text(
          node.displayValue,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _containerColor,
            fontSize: 13,
            fontFamily: 'Consolas',
          ),
        );
    }
  }
}
