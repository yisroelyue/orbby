import 'dart:io';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../models/favorite_item.dart';
import '../screens/menu_screen.dart';
import '../services/favorites_service.dart';
import 'base_panel.dart';

class FavoritesPanel extends BasePanel {
  const FavoritesPanel({super.key});

  @override
  State<FavoritesPanel> createState() => _FavoritesPanelState();
}

class _FavoritesPanelState extends BasePanelState<FavoritesPanel> {
  List<FavoriteFolder> _folders = [];
  bool _panelEnabled = true;
  bool _loading = true;

  @override
  String get panelTitle => '我的收藏';

  @override
  PanelIcon get panelIcon => const PanelIcon.svg('assets/svg/收藏.svg');

  @override
  VoidCallback? get onHeaderTap => () => _openEditor();

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  void initState() {
    super.initState();
    _fetch();
    MenuScreen.favoritesRefreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    MenuScreen.favoritesRefreshNotifier.removeListener(_onRefresh);
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
    MenuScreen.menuChannel.invokeMethod('open_favorites_editor', {
      'folderId': folderId ?? '',
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Padding(
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
      );
    }
    if (_folders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            '拖拽文件到悬浮球即可收藏',
            style: TextStyle(color: primaryText, fontSize: 13),
          ),
        ),
      );
    }

    final displayFolders = _folders.take(4).toList();
    final rowCount = (displayFolders.length / 4).ceil();
    final gridHeight = (rowCount * 80.0).clamp(0.0, 180.0);

    return SizedBox(
      height: gridHeight,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 2,
            crossAxisSpacing: 6,
            childAspectRatio: 0.9,
          ),
          itemCount: displayFolders.length,
          itemBuilder: (_, index) => _buildFolderTile(displayFolders[index]),
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
          width: 64,
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _hovered ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.elementBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.folder_rounded,
                    color: Color(0xFFE8B830),
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.folder.name,
                style: TextStyle(
                  color: widget.isDark ? Colors.white60 : const Color(0xFF888888),
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
