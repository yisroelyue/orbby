import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../config/panel_theme.dart';
import '../screens/menu_screen.dart';
import '../services/photo_wall_service.dart';

class PhotoWallPanel extends StatefulWidget {
  const PhotoWallPanel({super.key});

  @override
  State<PhotoWallPanel> createState() => _PhotoWallPanelState();
}

class _PhotoWallPanelState extends State<PhotoWallPanel> with PanelThemeMixin {
  List<String> _photos = [];
  bool _panelEnabled = true;
  bool _loading = true;
  bool _headerHovered = false;
  Timer? _shuffleTimer;

  @override
  void initState() {
    super.initState();
    _fetch();
    MenuScreen.refreshNotifier.addListener(_onRefresh);
    _shuffleTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _shuffle(),
    );
  }

  @override
  void dispose() {
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    _shuffleTimer?.cancel();
    super.dispose();
  }

  void _onRefresh() {
    _fetch();
  }

  void _shuffle() {
    if (_photos.length <= 1) return;
    setState(() {
      _photos = List<String>.from(_photos)..shuffle();
    });
  }

  Future<void> _fetch() async {
    final settings = await SettingsService.load();
    final photos = await PhotoWallService.loadPhotos();
    // 过滤掉已经不存在的文件
    final valid = photos.where((p) => File(p).existsSync()).toList();
    if (valid.length != photos.length) {
      await PhotoWallService.savePhotos(valid);
    }
    if (!mounted) return;
    setState(() {
      _panelEnabled = settings.showPhotoWallPanel;
      _photos = List<String>.from(valid)..shuffle();
      _loading = false;
    });
  }

  Future<void> _addPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files) {
      if (file.path != null) {
        await PhotoWallService.addPhoto(file.path!);
      }
    }
    _fetch();
  }

  Future<void> _removePhoto(String path) async {
    await PhotoWallService.removePhoto(path);
    _fetch();
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
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
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
        onTap: _addPhotos,
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
              Icon(
                Icons.photo_library_rounded,
                color: secondaryText,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '照片墙',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _headerHovered ? 1.0 : 0.0,
                child: Icon(
                  Icons.add_photo_alternate_rounded,
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
    if (_loading) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Text(
            '加载中...',
            style: TextStyle(color: mutedText, fontSize: 14),
          ),
        ),
      );
    }

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧大图
          Expanded(child: _buildLargePhoto(0)),
          const SizedBox(width: 10),
          // 右侧 2×2 正方形网格
          IntrinsicWidth(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(aspectRatio: 1, child: _buildSmallPhoto(1)),
                      const SizedBox(width: 6),
                      AspectRatio(aspectRatio: 1, child: _buildSmallPhoto(2)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(aspectRatio: 1, child: _buildSmallPhoto(3)),
                      const SizedBox(width: 6),
                      AspectRatio(aspectRatio: 1, child: _buildAddButton()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargePhoto(int index) {
    final borderRadius = BorderRadius.circular(10);
    if (index < _photos.length) {
      return _PhotoTile(
        path: _photos[index],
        borderRadius: borderRadius,
        onRemove: () => _removePhoto(_photos[index]),
        isDark: isDark,
      );
    }
    return _DefaultTile(
      assetPath: 'assets/png/photo/${index + 1}.png',
      borderRadius: borderRadius,
      isDark: isDark,
    );
  }

  Widget _buildSmallPhoto(int index) {
    final borderRadius = BorderRadius.circular(8);
    if (index < _photos.length) {
      return _PhotoTile(
        path: _photos[index],
        borderRadius: borderRadius,
        onRemove: () => _removePhoto(_photos[index]),
        isDark: isDark,
      );
    }
    return _DefaultTile(
      assetPath: 'assets/png/photo/${index + 1}.png',
      borderRadius: borderRadius,
      isDark: isDark,
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addPhotos,
      child: Container(
        decoration: BoxDecoration(
          color: hoverBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.add_rounded,
            color: tertiaryText,
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// 照片缩略图
class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    required this.path,
    required this.borderRadius,
    required this.onRemove,
    required this.isDark,
  });

  final String path;
  final BorderRadius borderRadius;
  final VoidCallback onRemove;
  final bool isDark;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(widget.path),
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => Container(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
                child: Icon(
                  Icons.broken_image_outlined,
                  color: widget.isDark ? Colors.white30 : const Color(0xFFCCCCCC),
                ),
              ),
            ),
            if (_hovering)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 默认占位图
class _DefaultTile extends StatelessWidget {
  const _DefaultTile({
    required this.assetPath,
    required this.borderRadius,
    required this.isDark,
  });

  final String assetPath;
  final BorderRadius borderRadius;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, e, s) => Container(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          child: Icon(
            Icons.image_outlined,
            color: isDark ? Colors.white24 : const Color(0xFFE8E8E8),
          ),
        ),
      ),
    );
  }
}
