import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/settings.dart';
import '../models/favorite_item.dart';
import '../screens/home_screen.dart';
import '../services/favorites_service.dart';
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
  bool _panelEnabled = true;
  bool _loading = true;

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  void initState() {
    super.initState();
    _fetch();
    HomeScreen.favoritesRefreshNotifier.addListener(_onRefresh);
    registerPanelEnabled((v) => _panelEnabled = v, (s) => s.showFavoritesPanel);
  }

  @override
  void dispose() {
    HomeScreen.favoritesRefreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final settings = await SettingsService.load();
    _panelEnabled = settings.showFavoritesPanel;
    if (!_panelEnabled) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final folders = await FavoritesService.loadFolders();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _loading = false;
    });
  }

  void _openEditor({String? folderId}) {
    HomeScreen.menuChannel.invokeMethod('open_favorites_editor', {
      'folderId': folderId ?? '',
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题栏
        GestureDetector(
          onTap: () => _openEditor(),
          child: Row(
            children: [
              SvgPicture.asset('assets/svg/收藏.svg', width: 22, height: 22),
              const SizedBox(width: 8),
              Text(
                '我的收藏',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
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
            child: Center(
              child: Text(
                '拖拽文件到悬浮球即可收藏',
                style: TextStyle(color: primaryText, fontSize: 13),
              ),
            ),
          ),
        ] else ...[
          Builder(
            builder: (context) {
              final displayFolders = _folders.take(4).toList();
              final rowCount = (displayFolders.length / 2).ceil();
              final gridHeight = (rowCount * 64.0).clamp(0.0, 180.0);

              return SizedBox(
                height: gridHeight,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3.2,
                  ),
                  itemCount: displayFolders.length,
                  itemBuilder: (_, index) => _buildFolderTile(displayFolders[index]),
                ),
              );
            },
          ),
        ],
      ],
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

  Widget _buildFolderTile(FavoriteFolder folder) {
    return _FolderTileWidget(
      folder: folder,
      isDark: isDark,
      elementBg: elementBg,
      hoverBg: hoverBg,
      onOpen: () => _openFolder(folder),
      onEdit: () => _openEditor(folderId: folder.id),
    );
  }
}

class _FolderTileWidget extends StatefulWidget {
  const _FolderTileWidget({
    required this.folder,
    required this.isDark,
    required this.elementBg,
    required this.hoverBg,
    required this.onOpen,
    required this.onEdit,
  });

  final FavoriteFolder folder;
  final bool isDark;
  final Color elementBg;
  final Color hoverBg;
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
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
                  child: const Icon(
                    Icons.folder_rounded,
                    color: Color(0xFFE8B830),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
