import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/settings.dart';
import '../config/panel_theme.dart';
import '../models/favorite_item.dart';
import '../screens/menu_screen.dart';
import '../services/favorites_service.dart';

class FavoritesPanel extends StatefulWidget {
  const FavoritesPanel({super.key});

  @override
  State<FavoritesPanel> createState() => _FavoritesPanelState();
}

class _FavoritesPanelState extends State<FavoritesPanel> with PanelThemeMixin {
  List<FavoriteFolder> _folders = [];
  bool _panelEnabled = true;
  bool _loading = true;
  bool _headerHovered = false;

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
  Widget build(BuildContext context) {
    if (!_panelEnabled && !_loading) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: panelBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
            if (_loading)
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
              )
            else
              _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _headerHovered = true),
      onExit: (_) => setState(() => _headerHovered = false),
      child: GestureDetector(
        onTap: () => _openEditor(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _headerHovered
                ? hoverBg
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/svg/收藏.svg',
                width: 22,
                height: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '我的收藏',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _headerHovered ? 1.0 : 0.0,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: mutedText,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
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

  Widget _buildFolderTile(FavoriteFolder folder) {
    return GestureDetector(
      onTap: () => _openEditor(folderId: folder.id),
      child: Container(
        width: 64,
        margin: const EdgeInsets.only(right: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: elementBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.folder_rounded,
                color: Color(0xFFE8B830),
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              folder.name,
              style: TextStyle(
                color: isDark ? Colors.white60 : const Color(0xFF888888),
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
