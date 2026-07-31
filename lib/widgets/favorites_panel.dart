import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/favorite_item.dart';
import '../screens/home_screen.dart';
import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import 'base_panel.dart';

class FavoritesPanel extends BasePanel {
  const FavoritesPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'favorites';

  @override
  State<FavoritesPanel> createState() => _FavoritesPanelState();
}

class _FavoritesPanelState extends BasePanelState<FavoritesPanel> {
  List<FavoriteFolder> _folders = [];
  int _totalCount = 0;
  int _uncategorizedCount = 0;
  bool _loading = true;

  // 文件夹颜色列表
  static const List<Color> _folderColors = [
    Color(0xFFE8B830), // 金色
    Color(0xFF4CAF50), // 绿色
    Color(0xFF2196F3), // 蓝色
    Color(0xFFFF7043), // 橙色
    Color(0xFF9C27B0), // 紫色
    Color(0xFF00BCD4), // 青色
    Color(0xFFFF5252), // 红色
    Color(0xFF7C4DFF), // 深紫色
  ];

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);
    if (!PanelCache.has('favorites_data')) {
      setState(() => _loading = true);
      PanelDataService.refreshFavorites();
    }
  }

  @override
  void dispose() {
    PanelCache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<Map<String, dynamic>>('favorites_data');
    if (cached != null && mounted) {
      setState(() {
        _folders = (cached['folders'] as List<FavoriteFolder>?) ?? [];
        _totalCount = (cached['allItems'] as List?)?.length ?? 0;
        _uncategorizedCount = cached['uncategorizedCount'] as int? ?? 0;
        _loading = false;
      });
    }
  }

  void _openEditor({String? folderId}) {
    HomeScreen.menuChannel.invokeMethod('open_favorites_editor', {
      'folderId': folderId ?? '',
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部：标题 + icon + 数量
            _buildHeaderTile(),
            const SizedBox(height: 12),
            // 内容区域
            if (_loading) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tertiaryText,
                    ),
                  ),
                ),
              ),
            ] else if (_folders.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '拖拽文件到悬浮球即可收藏',
                  style: TextStyle(color: primaryText, fontSize: 13),
                ),
              ),
            ] else ...[
              // 文件夹网格 - 每行两个
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3.0,
                ),
                itemCount: _folders.length + (_uncategorizedCount > 0 ? 1 : 0),
                itemBuilder: (_, index) {
                  if (index < _folders.length) {
                    final color = _folderColors[index % _folderColors.length];
                    return _buildFolderTile(_folders[index], color);
                  }
                  // 未分类目录
                  return _buildUncategorizedTile();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openFolder(FavoriteFolder folder) async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final folderPath = '$home\\.orbby\\favorites\\${folder.name}';
    final dir = Directory(folderPath);
    if (await dir.exists()) {
      await Process.start('explorer', [folderPath]);
    }
  }

  Future<void> _openUncategorized() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final folderPath = '$home\\.orbby\\favorites';
    final dir = Directory(folderPath);
    if (await dir.exists()) {
      await Process.start('explorer', [folderPath]);
    }
  }

  Widget _buildFolderTile(FavoriteFolder folder, Color color) {
    return _FolderTileWidget(
      folder: folder,
      isDark: isDark,
      elementBg: elementBg,
      hoverBg: hoverBg,
      folderColor: color,
      onOpen: () => _openFolder(folder),
      onEdit: () => _openEditor(folderId: folder.id),
    );
  }

  Widget _buildUncategorizedTile() {
    return _UncategorizedTileWidget(
      count: _uncategorizedCount,
      isDark: isDark,
      elementBg: elementBg,
      hoverBg: hoverBg,
      onOpen: _openUncategorized,
      onEdit: () => _openEditor(),
    );
  }

  Widget _buildHeaderTile() {
    return _HeaderTileWidget(
      totalCount: _totalCount,
      isDark: isDark,
      hoverBg: hoverBg,
      onOpen: () => _openEditor(),
    );
  }
}

class _HeaderTileWidget extends StatefulWidget {
  const _HeaderTileWidget({
    required this.totalCount,
    required this.isDark,
    required this.hoverBg,
    required this.onOpen,
  });

  final int totalCount;
  final bool isDark;
  final Color hoverBg;
  final VoidCallback onOpen;

  @override
  State<_HeaderTileWidget> createState() => _HeaderTileWidgetState();
}

class _HeaderTileWidgetState extends State<_HeaderTileWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'favorites',
                style: TextStyle(
                  color: widget.isDark ? Colors.white60 : const Color(0xFF888888),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: _hovered ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: SvgPicture.asset(
                      'assets/svg/收藏.svg',
                      width: 40,
                      height: 40,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '+${widget.totalCount}',
                    style: TextStyle(
                      color: widget.isDark ? Colors.white : const Color(0xFF333333),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderTileWidget extends StatefulWidget {
  const _FolderTileWidget({
    required this.folder,
    required this.isDark,
    required this.elementBg,
    required this.hoverBg,
    required this.folderColor,
    required this.onOpen,
    required this.onEdit,
  });

  final FavoriteFolder folder;
  final bool isDark;
  final Color elementBg;
  final Color hoverBg;
  final Color folderColor;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  State<_FolderTileWidget> createState() => _FolderTileWidgetState();
}

class _FolderTileWidgetState extends State<_FolderTileWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTap: widget.onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: _hovered ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.elementBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: widget.folderColor,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.folder.name,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white60 : const Color(0xFF888888),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UncategorizedTileWidget extends StatefulWidget {
  const _UncategorizedTileWidget({
    required this.count,
    required this.isDark,
    required this.elementBg,
    required this.hoverBg,
    required this.onOpen,
    required this.onEdit,
  });

  final int count;
  final bool isDark;
  final Color elementBg;
  final Color hoverBg;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  State<_UncategorizedTileWidget> createState() => _UncategorizedTileWidgetState();
}

class _UncategorizedTileWidgetState extends State<_UncategorizedTileWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTap: widget.onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: _hovered ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.elementBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    color: const Color(0xFF9E9E9E),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '未分类 (${widget.count})',
                  style: TextStyle(
                    color: widget.isDark ? Colors.white60 : const Color(0xFF888888),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
