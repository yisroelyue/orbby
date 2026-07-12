import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/todo_service.dart';
import '../widgets/interactive_icon.dart';

class TodoEditScreen extends StatefulWidget {
  const TodoEditScreen({super.key});

  static const editChannel = WindowMethodChannel(
    'orbby_todo_edit_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<TodoEditScreen> createState() => _TodoEditScreenState();
}

class _TodoEditScreenState extends State<TodoEditScreen>
    with SingleTickerProviderStateMixin {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  List<TodoItem> _uncompleted = [];
  List<TodoItem> _completed = [];
  bool _loading = true;
  String? _editingId;
  final _editController = TextEditingController();
  final _addController = TextEditingController();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAndFocus();
  }

  Future<void> _loadAndFocus() async {
    await _loadTodos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _editController.dispose();
    _addController.dispose();
    super.dispose();
  }

  Future<void> _loadTodos() async {
    setState(() => _loading = true);
    final todos = await TodoService.loadAll();
    if (!mounted) return;
    setState(() {
      _uncompleted = todos.where((t) => !t.completed).toList();
      _completed = todos.where((t) => t.completed).toList();
      _loading = false;
    });
  }

  Future<void> _toggleTodo(String id) async {
    await TodoService.toggle(id);
    TodoEditScreen.editChannel.invokeMethod('todo_saved');
    await _loadTodos();
  }

  Future<void> _deleteTodo(String id) async {
    _editingId = null;
    await TodoService.remove(id);
    TodoEditScreen.editChannel.invokeMethod('todo_saved');
    await _loadTodos();
  }

  Future<String?> _pickFile({required bool save}) async {
    if (Platform.isWindows) {
      final script = save
          ? r'[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")|Out-Null;'
              r'$d=New-Object System.Windows.Forms.SaveFileDialog;'
              r'$d.Filter="JSON (*.json)|*.json";'
              r'$d.FileName="orbby_todos.json";'
              r'if($d.ShowDialog() -eq "OK"){Write-Output $d.FileName}'
          : r'[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")|Out-Null;'
              r'$d=New-Object System.Windows.Forms.OpenFileDialog;'
              r'$d.Filter="JSON (*.json)|*.json";'
              r'if($d.ShowDialog() -eq "OK"){Write-Output $d.FileName}';
      try {
        final result = await Process.run(
          'powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script],
        );
        final path = (result.stdout as String).trim();
        return path.isNotEmpty ? path : null;
      } catch (_) {
        return null;
      }
    } else if (Platform.isMacOS) {
      try {
        final result = await Process.run('osascript', [
          '-e', save
              ? 'choose file name default name "orbby_todos.json"'
              : 'choose file of type {"public.json"}',
        ]);
        final out = (result.stdout as String).trim();
        if (out.isEmpty) return null;
        final path = out.startsWith('file://') ? Uri.decodeFull(out.substring(7)) : out;
        return path.replaceFirst(RegExp(r'^alias '), '');
      } catch (_) {
        return null;
      }
    } else {
      try {
        final args = save
            ? <String>['--file-selection', '--save', '--confirm-overwrite', '--file-filter=JSON | *.json', '--filename=orbby_todos.json']
            : <String>['--file-selection', '--file-filter=JSON | *.json'];
        final result = await Process.run('zenity', args);
        final path = (result.stdout as String).trim();
        return path.isNotEmpty ? path : null;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _exportTodos() async {
    final allTodos = [..._uncompleted, ..._completed];
    if (allTodos.isEmpty) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('没有笔记可导出'), duration: Duration(seconds: 1)),
      );
      return;
    }
    try {
      await windowManager.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final path = await _pickFile(save: true);
      await windowManager.show();
      if (path == null) return;
      final file = File(path);
      final json = const JsonEncoder.withIndent('  ').convert(allTodos.map((t) => t.toJson()).toList());
      await file.writeAsString(json);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('已导出 ${allTodos.length} 条笔记'), duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      await windowManager.show();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('导出失败: $e'), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _importTodos() async {
    try {
      await windowManager.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final path = await _pickFile(save: false);
      await windowManager.show();
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('文件不存在'), duration: Duration(seconds: 2)),
        );
        return;
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! List) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('无效的文件格式'), duration: Duration(seconds: 2)),
        );
        return;
      }

      final existing = await TodoService.loadAll();
      final existingTitles = existing.map((t) => t.title).toSet();
      int imported = 0;
      for (final item in json) {
        if (item is Map<String, dynamic> && item['title'] is String) {
          if (!existingTitles.contains(item['title'])) {
            final completed = item['completed'] as bool? ?? false;
            await TodoService.add(item['title'] as String, completed: completed);
            existingTitles.add(item['title'] as String);
            imported++;
          }
        }
      }

      TodoEditScreen.editChannel.invokeMethod('todo_saved');
      await _loadTodos();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('已导入 $imported 条笔记'), duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      await windowManager.show();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('导入失败: $e'), duration: const Duration(seconds: 2)),
      );
    }
  }

  void _startEdit(TodoItem item) {
    setState(() {
      _editingId = item.id;
      _editController.text = item.title;
    });
  }

  Future<void> _finishEdit() async {
    final text = _editController.text.trim();
    final id = _editingId;
    if (id != null && text.isNotEmpty) {
      await TodoService.updateTitle(id, text);
      TodoEditScreen.editChannel.invokeMethod('todo_saved');
      await _loadTodos();
    }
    setState(() => _editingId = null);
    _editController.clear();
  }

  Future<void> _addTodo() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    _addController.clear();
    await TodoService.add(text);
    TodoEditScreen.editChannel.invokeMethod('todo_saved');
    await _loadTodos();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSansSC'),
      scaffoldMessengerKey: _messengerKey,
      navigatorKey: _navigatorKey,
      home: Scaffold(
          backgroundColor: const Color(0xFF2A2A2A),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleBar(),
                  const SizedBox(height: 10),
                  if (!_loading) _buildTabBar(),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.white54,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else
                    Expanded(child: _buildTabViews()),
                  const SizedBox(height: 8),
                  _buildAddRow(),
                ],
              ),
            ),
        ),
    );
  }

  Widget _buildTextButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 28,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: Colors.white54,
          textStyle: const TextStyle(fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Row(
      children: [
        const Icon(Icons.edit_note_rounded, color: Colors.white70, size: 22),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '笔记管理',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _buildTextButton('导入', _importTodos),
        const SizedBox(width: 4),
        _buildTextButton('导出', _exportTodos),
        const SizedBox(width: 8),
        InteractiveIcon(
          onTap: () => windowManager.hide(),
          child: const Icon(Icons.close, color: Colors.white54, size: 20),
        ),
      ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: false,
      dividerHeight: 0,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white38,
      indicatorColor: Colors.greenAccent,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13),
      tabs: [
        Tab(text: '待处理  ${_uncompleted.length}'),
        Tab(text: '已完成  ${_completed.length}'),
      ],
    );
  }

  Widget _buildTabViews() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildTodoList(_uncompleted),
        _buildTodoList(_completed),
      ],
    );
  }

  Widget _buildTodoList(List<TodoItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          items == _uncompleted ? '暂无笔记' : '暂无已完成项',
          style: const TextStyle(color: Colors.white24, fontSize: 13),
        ),
      );
    }
    return ListView(
      primary: true,
      padding: EdgeInsets.zero,
      children: items.map(_buildTodoItem).toList(),
    );
  }

  Widget _buildTodoItem(TodoItem item) {
    final isEditing = _editingId == item.id;
    final isCompleted = item.completed;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 2),
        padding: EdgeInsets.symmetric(
          horizontal: isEditing ? 12 : 8,
          vertical: isEditing ? 10 : 6,
        ),
        decoration: BoxDecoration(
          color: isEditing
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(isEditing ? 12 : 8),
          border: isEditing
              ? Border.all(color: Colors.white.withValues(alpha: 0.12))
              : null,
        ),
        child: isEditing
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _toggleTodo(item.id),
                        child: Icon(
                          isCompleted ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                          color: isCompleted ? Colors.greenAccent : Colors.white38,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (item.important)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Colors.amberAccent.withValues(alpha: 0.85),
                          ),
                        ),
                      const Text(
                        '编辑中',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _editController,
                    autofocus: true,
                    maxLines: 6,
                    minLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onSubmitted: (_) => _finishEdit(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 30,
                      child: ElevatedButton(
                        onPressed: _finishEdit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent.withValues(alpha: 0.85),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text('保存', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  if (item.important)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amberAccent.withValues(alpha: 0.85),
                      ),
                    ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _startEdit(item),
                      child: Text(
                        item.title,
                        style: TextStyle(
                          color: isCompleted ? Colors.white38 : Colors.white,
                          fontSize: 14,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: Colors.white38,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (isCompleted)
                    InteractiveIcon(
                      size: 24,
                      onTap: () => _toggleTodo(item.id),
                      child: const Icon(Icons.undo_rounded, color: Colors.white38, size: 14),
                    )
                  else
                    InteractiveIcon(
                      size: 24,
                      onTap: () => _toggleTodo(item.id),
                      child: const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 14),
                    ),
                  InteractiveIcon(
                    size: 24,
                    onTap: () => _startEdit(item),
                    child: const Icon(Icons.edit, color: Colors.white24, size: 14),
                  ),
                  InteractiveIcon(
                    size: 24,
                    onTap: () => _deleteTodo(item.id),
                    child: const Icon(Icons.close, color: Colors.white24, size: 14),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAddRow() {
    return Row(
      children: [
        const Icon(Icons.add, color: Colors.white38, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _addController,
            cursorColor: Colors.white70,
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: '添加新笔记...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: InputBorder.none,
            ),
          ),
        ),
        InteractiveIcon(
          size: 32,
          onTap: _addTodo,
          child: const Icon(Icons.send_rounded, color: Colors.white54, size: 18),
        ),
      ],
    );
  }
}
