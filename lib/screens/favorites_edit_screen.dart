import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/favorite_item.dart';
import '../services/favorites_service.dart';
import '../widgets/interactive_icon.dart';

class FavoritesEditScreen extends StatefulWidget {
  const FavoritesEditScreen({
    super.key,
    this.initialFolderId,
  });

  final String? initialFolderId;

  static const editChannel = WindowMethodChannel(
    'orbby_favorites_edit_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<FavoritesEditScreen> createState() => _FavoritesEditScreenState();
}

class _FavoritesEditScreenState extends State<FavoritesEditScreen>
    with TickerProviderStateMixin {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  List<FavoriteFolder> _folders = [];
  Map<String?, List<FavoriteItem>> _itemsByFolder = {};
  bool _loading = true;
  late TabController _tabController;
  int _tabIndex = 0;

  // Inline dialog state
  bool _showNewFolderDialog = false;
  bool _showDeleteFolderDialog = false;
  String? _deleteTargetFolderId;
  bool _showMoveDialog = false;
  String? _moveTargetItemId;
  final _newFolderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _tabIndex) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
    _loadData();
    if (widget.initialFolderId != null && widget.initialFolderId!.isNotEmpty) {
      _switchToFolder(widget.initialFolderId!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _newFolderController.dispose();
    super.dispose();
  }

  String? _folderIdForTab(int index) {
    if (index == 0) return null; // uncategorized
    final fi = index - 1;
    if (fi < _folders.length) return _folders[fi].id;
    return null;
  }

  void _switchToFolder(String folderId) {
    final idx = _folders.indexWhere((f) => f.id == folderId);
    if (idx >= 0 && _tabController.length > idx + 1) {
      _tabController.animateTo(idx + 1);
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final folders = await FavoritesService.loadFolders();
    final allItems = await FavoritesService.loadAllItems();
    final byFolder = <String?, List<FavoriteItem>>{};
    byFolder[null] = [];
    for (final f in folders) {
      byFolder[f.id] = [];
    }
    for (final item in allItems) {
      (byFolder[item.folderId] ??= []).add(item);
    }
    if (!mounted) return;
    // Don't change tabCount while animating
    final newCount = folders.length + 1;
    if (_tabController.length != newCount) {
      // Re-create TabController when folder count changes
      final oldIndex = _tabController.index;
      _tabController.dispose();
      _tabController = TabController(
        length: newCount,
        vsync: this,
        initialIndex: oldIndex.clamp(0, newCount - 1),
      );
      _tabController.addListener(() {
        if (_tabController.index != _tabIndex) {
          setState(() => _tabIndex = _tabController.index);
        }
      });
    }
    setState(() {
      _folders = folders;
      _itemsByFolder = byFolder;
      _tabIndex = _tabController.index;
      _loading = false;
    });
  }

  // ── New folder dialog ────────────────────────────────────

  void _openNewFolderDialog() {
    if (_folders.length >= 8) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('最多创建8个收藏夹'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    _newFolderController.clear();
    setState(() => _showNewFolderDialog = true);
  }

  Future<void> _confirmNewFolder() async {
    final name = _newFolderController.text.trim();
    setState(() => _showNewFolderDialog = false);
    _newFolderController.clear();
    if (name.isEmpty) return;
    await FavoritesService.addFolder(name);
    FavoritesEditScreen.editChannel.invokeMethod('favorites_changed');
    await _loadData();
    // Switch to the new folder tab
    final idx = _folders.indexWhere((f) => f.name == name);
    if (idx >= 0) {
      _tabController.animateTo(idx + 1);
    }
  }

  void _cancelNewFolder() {
    setState(() => _showNewFolderDialog = false);
    _newFolderController.clear();
  }

  // ── Delete folder ────────────────────────────────────────

  void _openDeleteFolderDialog(String id) {
    setState(() {
      _showDeleteFolderDialog = true;
      _deleteTargetFolderId = id;
    });
  }

  Future<void> _confirmDeleteFolder() async {
    final id = _deleteTargetFolderId;
    setState(() {
      _showDeleteFolderDialog = false;
      _deleteTargetFolderId = null;
    });
    if (id == null) return;
    await FavoritesService.removeFolder(id);
    FavoritesEditScreen.editChannel.invokeMethod('favorites_changed');
    await _loadData();
  }

  void _cancelDeleteFolder() {
    setState(() {
      _showDeleteFolderDialog = false;
      _deleteTargetFolderId = null;
    });
  }

  // ── Move item ────────────────────────────────────────────

  void _openMoveDialog(String itemId) {
    setState(() {
      _showMoveDialog = true;
      _moveTargetItemId = itemId;
    });
  }

  Future<void> _moveToFolder(String? folderId) async {
    final itemId = _moveTargetItemId;
    setState(() {
      _showMoveDialog = false;
      _moveTargetItemId = null;
    });
    if (itemId == null) return;
    await FavoritesService.moveToFolder(itemId, folderId);
    FavoritesEditScreen.editChannel.invokeMethod('favorites_changed');
    await _loadData();
  }

  void _cancelMove() {
    setState(() {
      _showMoveDialog = false;
      _moveTargetItemId = null;
    });
  }

  // ── Delete item ──────────────────────────────────────────

  Future<void> _deleteItem(String id) async {
    await FavoritesService.remove(id);
    FavoritesEditScreen.editChannel.invokeMethod('favorites_changed');
    await _loadData();
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final folderId = _folderIdForTab(_tabIndex);
    for (final file in result.files) {
      if (file.path == null) continue;
      await FavoritesService.add(file.path!, folderId: folderId);
    }
    FavoritesEditScreen.editChannel.invokeMethod('favorites_changed');
    await _loadData();
  }

  void _openFile(String filePath) {
    if (Platform.isWindows) {
      Process.run('explorer', [filePath]);
    } else if (Platform.isMacOS) {
      Process.run('open', [filePath]);
    } else {
      Process.run('xdg-open', [filePath]);
    }
  }

  IconData _fileIcon(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'bmp': case 'webp':
        return Icons.image;
      case 'mp4': case 'avi': case 'mov': case 'mkv': return Icons.movie;
      case 'mp3': case 'wav': case 'flac': case 'aac': return Icons.music_note;
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz':
        return Icons.folder_zip;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'ppt': case 'pptx': return Icons.slideshow;
      case 'txt': case 'md': case 'json': case 'xml': case 'yaml': case 'yml':
        return Icons.article;
      case 'exe': case 'dll': return Icons.terminal;
      default: return Icons.insert_drive_file;
    }
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: const Color(0xFFF5F5F5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Stack(
                children: [
                  Column(
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
                              color: Colors.black26, strokeWidth: 2,
                            ),
                          ),
                        )
                      else
                        Expanded(child: _buildTabViews()),
                    ],
                  ),
                  if (_showNewFolderDialog) _buildOverlay(_buildNewFolderDialog()),
                  if (_showDeleteFolderDialog) _buildOverlay(_buildDeleteFolderDialog()),
                  if (_showMoveDialog) _buildOverlay(_buildMoveDialog()),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Microsoft YaHei'),
      scaffoldMessengerKey: _messengerKey,
      home: body,
    );
  }

  Widget _buildOverlay(Widget child) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(child: child),
      ),
    );
  }

  // ── Title bar ────────────────────────────────────────────

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Row(
      children: [
        const Icon(Icons.folder_rounded, color: Colors.black54, size: 22),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('收藏管理',
            style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        InteractiveIcon(
          size: 30,
          onTap: _uploadFile,
          child: const Icon(Icons.add, color: Colors.black87, size: 20),
        ),
        const SizedBox(width: 4),
        InteractiveIcon(
          size: 30,
          onTap: _openNewFolderDialog,
          child: const Icon(Icons.create_new_folder, color: Colors.black87, size: 20),
        ),
        const SizedBox(width: 4),
        InteractiveIcon(
          onTap: () => windowManager.hide(),
          child: const Icon(Icons.close, color: Colors.black54, size: 20),
        ),
      ],
      ),
    );
  }

  // ── Tab bar (matching TodoEditScreen style) ──────────────

  Widget _buildTabBar() {
    final tabs = <Widget>[
      Tab(text: '未分类  ${_itemsByFolder[null]?.length ?? 0}'),
    ];
    for (final folder in _folders) {
      final count = _itemsByFolder[folder.id]?.length ?? 0;
      tabs.add(Tab(text: '${folder.name}  $count'));
    }

    return Row(
      children: [
        Expanded(
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            dividerHeight: 0,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: Colors.black87,
            unselectedLabelColor: Colors.black38,
            indicatorColor: Colors.greenAccent,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: tabs,
            onTap: (_) {},
          ),
        ),
        // Delete button for active folder tab (not for uncategorized)
        if (_tabIndex > 0 && _tabIndex - 1 < _folders.length) ...[
          const SizedBox(width: 4),
          InteractiveIcon(
            size: 28,
            onTap: () => _openDeleteFolderDialog(_folders[_tabIndex - 1].id),
            child: const Icon(Icons.delete_outline, color: Colors.black54, size: 18),
          ),
        ],
      ],
    );
  }

  Widget _buildTabViews() {
    final views = <Widget>[];
    // Uncategorized
    views.add(_buildFileList(folderId: null));
    // Each folder
    for (final folder in _folders) {
      views.add(_buildFileList(folderId: folder.id));
    }
    return TabBarView(
      controller: _tabController,
      children: views,
    );
  }

  Widget _buildFileList({required String? folderId}) {
    final items = _itemsByFolder[folderId] ?? [];
    if (items.isEmpty) {
      return Center(
        child: Text(
          folderId == null ? '暂无未分类文件' : '此收藏夹为空',
          style: const TextStyle(color: Colors.black26, fontSize: 13),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: items.map((item) => _buildFileItem(item, folderId)).toList(),
    );
  }

  Widget _buildFileItem(FavoriteItem item, String? currentFolderId) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openFile(item.filePath),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(_fileIcon(item.filePath), size: 18, color: Colors.black38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.displayName,
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Move button (only show if there are folders to move to)
              if (_folders.isNotEmpty)
                InteractiveIcon(
                  size: 24,
                  onTap: () => _openMoveDialog(item.id),
                  child: const Icon(Icons.drive_file_move_outline,
                      color: Colors.black54, size: 16),
                ),
              InteractiveIcon(
                size: 24,
                onTap: () => _deleteItem(item.id),
                child: const Icon(Icons.close, color: Colors.black38, size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────

  Widget _buildNewFolderDialog() {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('新建收藏夹',
              style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _newFolderController,
            autofocus: true,
            cursorColor: Colors.black54,
            style: const TextStyle(color: Colors.black87, fontSize: 15),
            decoration: InputDecoration(
              hintText: '输入收藏夹名称...',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.35)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (_) => _confirmNewFolder(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelNewFolder,
                child: const Text('取消', style: TextStyle(color: Colors.black54)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _confirmNewFolder,
                child: const Text('创建', style: TextStyle(color: Colors.black87)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteFolderDialog() {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('删除收藏夹',
              style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text('删除后其中的文件将移至未分类',
              style: TextStyle(color: Colors.black54, fontSize: 14)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelDeleteFolder,
                child: const Text('取消', style: TextStyle(color: Colors.black54)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _confirmDeleteFolder,
                child: const Text('删除', style: TextStyle(color: Colors.black87)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoveDialog() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('移动到收藏夹',
              style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ..._buildMoveOptions(),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _cancelMove,
              child: const Text('取消', style: TextStyle(color: Colors.black54)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMoveOptions() {
    final widgets = <Widget>[];

    // Option to move to uncategorized
    if (_tabIndex != 0) {
      widgets.add(_buildMoveOption(null, '未分类', Icons.folder_open));
    }

    for (final folder in _folders) {
      final fid = _folderIdForTab(_tabIndex);
      if (folder.id == fid) continue; // skip current folder
      widgets.add(_buildMoveOption(folder.id, folder.name, Icons.folder));
    }

    if (widgets.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('没有可用的目标收藏夹',
            style: TextStyle(color: Colors.black38, fontSize: 13)),
      ));
    }

    return widgets;
  }

  Widget _buildMoveOption(String? folderId, String name, IconData icon) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: () => _moveToFolder(folderId),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          alignment: Alignment.centerLeft,
          foregroundColor: Colors.black87,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
