// 工具注册中心
// 从 orbby-agent/src/tools/registry.ts 迁移
// Flutter 不支持动态 import，改为静态注册模式

import 'types.dart';

class ToolRegistry {
  /// name -> tool 定义
  final Map<String, ToolDefinition> _tools = {};

  /// 获取所有已注册工具
  Map<String, ToolDefinition> get tools => Map.unmodifiable(_tools);

  /// 注册单个工具
  void register(ToolDefinition tool) {
    _tools[tool.name] = tool;
  }

  /// 批量注册工具
  void registerAll(List<ToolDefinition> tools) {
    for (final tool in tools) {
      _tools[tool.name] = tool;
    }
  }

  /// 返回给 LLM 的工具定义列表
  List<ToolCallDefinition> getToolDefinitions() {
    return _tools.values
        .map((t) => ToolCallDefinition(
              name: t.name,
              description: t.description,
              parameters: t.parameters,
            ))
        .toList();
  }

  /// 获取轻量工具索引，只包含名称和描述，不包含参数 schema
  /// 用于延迟加载工具，避免每次请求发送所有完整定义
  List<ToolIndex> getToolIndex({List<String>? excludeNames}) {
    final excluded = excludeNames != null ? Set.from(excludeNames) : <String>{};
    return _tools.values
        .where((tool) => !excluded.contains(tool.name))
        .map((tool) => ToolIndex(
              name: tool.name,
              description: tool.description,
            ))
        .toList();
  }

  /// 按工具名称获取定义
  List<ToolCallDefinition> getToolDefinitionsByNames(List<String> names) {
    final wanted = Set.from(names);
    return _tools.values
        .where((tool) => wanted.contains(tool.name))
        .map((t) => ToolCallDefinition(
              name: t.name,
              description: t.description,
              parameters: t.parameters,
            ))
        .toList();
  }

  /// 执行指定工具
  Future<String> executeTool(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      return '错误：未找到工具 "$name"';
    }

    try {
      final result = await tool.execute(args);
      return result;
    } catch (err) {
      return '工具 "$name" 执行失败: $err';
    }
  }
}
