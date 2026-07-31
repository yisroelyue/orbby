import 'dart:io';

import 'types.dart';
import 'tool_policy.dart';
import 'tools/create_file_tool.dart';
import 'tools/read_file_tool.dart';
import 'tools/edit_file_tool.dart';
import 'tools/delete_file_tool.dart';
import 'tools/list_directory_tool.dart';
import 'tools/search_files_tool.dart';
import 'tools/execute_command_tool.dart';
import 'tools/open_chrome_tool.dart';
import 'tools/news_search_tool.dart';

class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};
  final ToolPolicy policy;

  ToolRegistry({ToolPolicy? policy})
    : policy = policy ?? ToolPolicy(workspaceRoot: Directory.current.path);
  Map<String, ToolDefinition> get tools => Map.unmodifiable(_tools);

  void register(ToolDefinition tool) => _tools[tool.name] = tool;
  void registerAll(List<ToolDefinition> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  void initBuiltinTools() => registerAll([
    createFileTool,
    readFileTool,
    editFileTool,
    deleteFileTool,
    listDirectoryTool,
    searchFilesTool,
    executeCommandTool,
    openChromeTool,
    newsSearchTool,
  ]);

  List<ToolCallDefinition> getToolDefinitions() => _tools.values
      .map(
        (t) => ToolCallDefinition(
          name: t.name,
          description: t.description,
          parameters: t.parameters,
        ),
      )
      .toList();

  List<ToolIndex> getToolIndex({List<String>? excludeNames}) {
    final excluded = excludeNames != null
        ? Set<String>.from(excludeNames)
        : <String>{};
    return _tools.values
        .where((t) => !excluded.contains(t.name))
        .map((t) => ToolIndex(name: t.name, description: t.description))
        .toList();
  }

  List<ToolCallDefinition> getToolDefinitionsByNames(List<String> names) {
    final wanted = Set<String>.from(names);
    return _tools.values
        .where((t) => wanted.contains(t.name))
        .map(
          (t) => ToolCallDefinition(
            name: t.name,
            description: t.description,
            parameters: t.parameters,
          ),
        )
        .toList();
  }

  Future<ToolResult> executeTool(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null)
      return ToolResult.error('Tool not found: $name', code: 'tool_not_found');
    final denied = policy.validate(name, args);
    if (denied != null) return ToolResult.error(denied, code: 'policy_denied');
    try {
      return ToolResult.ok(await tool.execute(args));
    } catch (error) {
      return ToolResult.error(
        'Tool $name failed: $error',
        code: 'tool_exception',
        retryable: true,
      );
    }
  }
}
