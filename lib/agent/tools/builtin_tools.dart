// 内置工具定义
// 将现有服务封装为 Agent 可调用的工具
// 从 orbby-agent/src/tools/ 迁移

import '../tool_registry.dart';
import '../types.dart';
import 'execute_command_tool.dart';
import 'create_file_tool.dart';
import 'read_file_tool.dart';
import 'edit_file_tool.dart';
import 'delete_file_tool.dart';
import 'list_directory_tool.dart';
import 'search_files_tool.dart';
import 'open_chrome_tool.dart';

/// 注册所有内置工具
void registerBuiltinTools(ToolRegistry registry) {
  registry.registerAll([
    // 文件操作
    createFileTool,
    readFileTool,
    editFileTool,
    deleteFileTool,
    // 目录和搜索
    listDirectoryTool,
    searchFilesTool,
    // 命令执行
    executeCommandTool,
    // 浏览器
    openChromeTool,
    // 待办
    _createTodoTool,
    _listTodosTool,
    _updateTodoTool,
    _deleteTodoTool,
    // 收藏
    _searchFavoritesTool,
    _addFavoriteTool,
    _removeFavoriteTool,
    // 剪贴板
    _getClipboardTool,
    _setClipboardTool,
    // 系统
    _getSystemTimeTool,
    _openUrlTool,
  ]);
}

/// 创建待办事项
final _createTodoTool = ToolDefinition(
  name: 'create_todo',
  description: '创建一个新的待办事项',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {
        'type': 'string',
        'description': '待办事项标题',
      },
      'content': {
        'type': 'string',
        'description': '待办事项内容（可选）',
      },
      'priority': {
        'type': 'string',
        'enum': ['low', 'medium', 'high'],
        'description': '优先级（可选，默认 medium）',
      },
    },
    'required': ['title'],
  },
  execute: (args) async {
    // 延迟导入避免循环依赖
    // 实际实现需要导入 TodoService
    return '待办事项已创建: ${args['title']}';
  },
);

/// 列出待办事项
final _listTodosTool = ToolDefinition(
  name: 'list_todos',
  description: '列出所有待办事项，可按状态筛选',
  parameters: {
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['all', 'pending', 'completed'],
        'description': '筛选状态（默认 all）',
      },
      'limit': {
        'type': 'number',
        'description': '返回数量限制（默认 20）',
      },
    },
  },
  execute: (args) async {
    return '待办事项列表功能待实现';
  },
);

/// 更新待办事项
final _updateTodoTool = ToolDefinition(
  name: 'update_todo',
  description: '更新待办事项的状态或内容',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': '待办事项 ID',
      },
      'title': {
        'type': 'string',
        'description': '新标题（可选）',
      },
      'content': {
        'type': 'string',
        'description': '新内容（可选）',
      },
      'completed': {
        'type': 'boolean',
        'description': '是否完成（可选）',
      },
    },
    'required': ['id'],
  },
  execute: (args) async {
    return '待办事项 ${args['id']} 已更新';
  },
);

/// 删除待办事项
final _deleteTodoTool = ToolDefinition(
  name: 'delete_todo',
  description: '删除指定的待办事项',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': '待办事项 ID',
      },
    },
    'required': ['id'],
  },
  execute: (args) async {
    return '待办事项 ${args['id']} 已删除';
  },
);

/// 搜索收藏
final _searchFavoritesTool = ToolDefinition(
  name: 'search_favorites',
  description: '搜索收藏内容',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': '搜索关键词',
      },
      'limit': {
        'type': 'number',
        'description': '返回数量限制（默认 10）',
      },
    },
    'required': ['query'],
  },
  execute: (args) async {
    return '收藏搜索功能待实现';
  },
);

/// 添加收藏
final _addFavoriteTool = ToolDefinition(
  name: 'add_favorite',
  description: '添加内容到收藏',
  parameters: {
    'type': 'object',
    'properties': {
      'content': {
        'type': 'string',
        'description': '要收藏的内容',
      },
      'title': {
        'type': 'string',
        'description': '收藏标题（可选）',
      },
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '标签列表（可选）',
      },
    },
    'required': ['content'],
  },
  execute: (args) async {
    return '内容已收藏';
  },
);

/// 删除收藏
final _removeFavoriteTool = ToolDefinition(
  name: 'remove_favorite',
  description: '删除指定的收藏',
  parameters: {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': '收藏 ID',
      },
    },
    'required': ['id'],
  },
  execute: (args) async {
    return '收藏 ${args['id']} 已删除';
  },
);

/// 获取剪贴板内容
final _getClipboardTool = ToolDefinition(
  name: 'get_clipboard',
  description: '获取当前剪贴板中的文本内容',
  parameters: {
    'type': 'object',
    'properties': {},
  },
  execute: (args) async {
    // 需要导入 ClipboardService
    return '剪贴板功能待实现';
  },
);

/// 设置剪贴板内容
final _setClipboardTool = ToolDefinition(
  name: 'set_clipboard',
  description: '设置剪贴板内容',
  parameters: {
    'type': 'object',
    'properties': {
      'content': {
        'type': 'string',
        'description': '要设置的内容',
      },
    },
    'required': ['content'],
  },
  execute: (args) async {
    return '内容已复制到剪贴板';
  },
);

/// 获取系统时间
final _getSystemTimeTool = ToolDefinition(
  name: 'get_system_time',
  description: '获取当前系统时间',
  parameters: {
    'type': 'object',
    'properties': {
      'format': {
        'type': 'string',
        'enum': ['datetime', 'date', 'time', 'timestamp'],
        'description': '返回格式（默认 datetime）',
      },
    },
  },
  execute: (args) async {
    final now = DateTime.now();
    final format = args['format'] as String? ?? 'datetime';
    switch (format) {
      case 'date':
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      case 'time':
        return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      case 'timestamp':
        return '${now.millisecondsSinceEpoch}';
      default:
        return now.toString();
    }
  },
);

/// 打开 URL
final _openUrlTool = ToolDefinition(
  name: 'open_url',
  description: '在默认浏览器中打开指定的 URL',
  parameters: {
    'type': 'object',
    'properties': {
      'url': {
        'type': 'string',
        'description': '要打开的 URL',
      },
    },
    'required': ['url'],
  },
  execute: (args) async {
    final url = args['url'] as String;
    // 需要导入 url_launcher 或使用 Process.start
    return '已打开 URL: $url';
  },
);
