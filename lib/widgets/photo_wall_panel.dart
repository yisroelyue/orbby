import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import '../services/photo_wall_service.dart';
import 'base_panel.dart';

class PhotoWallPanel extends BasePanel {
  const PhotoWallPanel({super.key});

  @override
  State<PhotoWallPanel> createState() => _PhotoWallPanelState();
}

class _PhotoWallPanelState extends BasePanelState<PhotoWallPanel> {
  List<String> _photos = [];
  bool _panelEnabled = true;
  bool _loading = true;
  Timer? _shuffleTimer;

  @override
  String get panelTitle => '照片墙';

  @override
  PanelIcon get panelIcon => const PanelIcon.icon(Icons.photo_library_rounded);

  @override
  Color get panelIconColor => secondaryText;

  @override
  VoidCallback? get onHeaderTap => _addPhotos;

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  List<Widget> buildHeaderActions() {
    return [
      AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: 1.0,
        child: Icon(
          Icons.add_photo_alternate_rounded,
          color: mutedText,
          size: 20,
        ),
      ),
    ];
  }

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
  Widget buildHeader() {
    return _PhotoWallHeader(
      icon: buildIconWidget(),
      title: panelTitle,
      titleColor: primaryText,
      hoverBg: hoverBg,
      mutedText: mutedText,
      onTap: _addPhotos,
    );
  }

  @override
  Widget buildContent(BuildContext context) {
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
          Expanded(child: _buildLargePhoto(0)),
          const SizedBox(width: 10),
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

/// PhotoWallPanel 专用 header，带添加照片图标
class _PhotoWallHeader extends StatefulWidget {
  const _PhotoWallHeader({
    required this.icon,
    required this.title,
    required this.titleColor,
    required this.hoverBg,
    required this.mutedText,
    this.onTap,
  });

  final Widget icon;
  final String title;
  final Color titleColor;
  final Color hoverBg;
  final Color mutedText;
  final VoidCallback? onTap;

  @override
  State<_PhotoWallHeader> createState() => _PhotoWallHeaderState();
}

class _PhotoWallHeaderState extends State<_PhotoWallHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              widget.icon,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: widget.titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _hovered ? 1.0 : 0.0,
                child: Icon(
                  Icons.add_photo_alternate_rounded,
                  color: widget.mutedText,
                  size: 20,
                ),
              ),
            ],
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
