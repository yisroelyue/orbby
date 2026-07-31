/// JSON 节点类型。
enum JsonNodeType {
  object,
  array,
  string_,
  number_,
  boolean_,
  null_,
}

/// JSON 树节点模型，由 [JsonNode.fromValue] 递归构建。
class JsonNode {
  JsonNode({
    this.key,
    required this.value,
    required this.type,
    this.depth = 0,
    this.isExpanded = true,
    this.children,
  });

  /// 键名。null 表示根节点或数组元素。
  final String? key;

  /// 原始 JSON 值。
  final dynamic value;

  /// 节点类型。
  final JsonNodeType type;

  /// 嵌套深度，用于缩进计算。
  final int depth;

  /// 对象/数组是否展开。
  bool isExpanded;

  /// 对象/数组的子节点；基础类型节点为 null。
  final List<JsonNode>? children;

  /// 子节点数量。
  int get childCount => children?.length ?? 0;

  /// 是否可折叠（对象/数组）。
  bool get isContainer => children != null;

  /// 长字符串截断显示。
  static String _truncate(String s, [int max = 80]) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  /// 值展示文本（不包含引号包裹，由调用方决定样式）。
  String get displayValue {
    switch (type) {
      case JsonNodeType.string_:
        return _truncate(value as String? ?? '');
      case JsonNodeType.number_:
        return value.toString();
      case JsonNodeType.boolean_:
        return value.toString();
      case JsonNodeType.null_:
        return 'null';
      case JsonNodeType.object:
        return '{$childCount keys}';
      case JsonNodeType.array:
        return '[$childCount items]';
    }
  }

  /// 类型标签文本。
  String get typeLabel {
    switch (type) {
      case JsonNodeType.object:
        return 'object';
      case JsonNodeType.array:
        return 'array';
      case JsonNodeType.string_:
        return 'string';
      case JsonNodeType.number_:
        return 'number';
      case JsonNodeType.boolean_:
        return 'boolean';
      case JsonNodeType.null_:
        return 'null';
    }
  }

  /// 从任意 JSON 值递归构建树。
  factory JsonNode.fromValue(
    dynamic value, {
    String? key,
    int depth = 0,
  }) {
    if (value is Map) {
      final children = <JsonNode>[
        for (final entry in value.entries)
          JsonNode.fromValue(
            entry.value,
            key: entry.key.toString(),
            depth: depth + 1,
          ),
      ];
      return JsonNode(
        key: key,
        value: value,
        type: JsonNodeType.object,
        depth: depth,
        children: children,
      );
    }
    if (value is List) {
      final children = <JsonNode>[
        for (int i = 0; i < value.length; i++)
          JsonNode.fromValue(value[i], key: null, depth: depth + 1),
      ];
      return JsonNode(
        key: key,
        value: value,
        type: JsonNodeType.array,
        depth: depth,
        children: children,
      );
    }
    final type = value is String
        ? JsonNodeType.string_
        : value is num
            ? JsonNodeType.number_
            : value is bool
                ? JsonNodeType.boolean_
                : JsonNodeType.null_;
    return JsonNode(
      key: key,
      value: value,
      type: type,
      depth: depth,
    );
  }
}
