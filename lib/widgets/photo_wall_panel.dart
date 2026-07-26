import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';
import '../services/photo_wall_service.dart';
import 'base_panel.dart';

class PhotoWallPanel extends BasePanel {
  const PhotoWallPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'photo_wall';

  @override
  State<PhotoWallPanel> createState() => _PhotoWallPanelState();
}

class _PhotoWallPanelState extends BasePanelState<PhotoWallPanel> {
  List<String> _photos = [];
  bool _loading = true;
  bool _hovered = false;
  Timer? _shuffleTimer;

  @override
  EdgeInsetsGeometry get panelPadding => EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    _fetch();
    HomeScreen.refreshNotifier.addListener(_onRefresh);
    _shuffleTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _shuffle(),
    );
  }

  @override
  void dispose() {
    HomeScreen.refreshNotifier.removeListener(_onRefresh);
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
    final photos = await PhotoWallService.loadPhotos();
    final valid = photos.where((p) => File(p).existsSync()).toList();
    if (valid.length != photos.length) {
      await PhotoWallService.savePhotos(valid);
    }
    if (!mounted) return;
    setState(() {
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

  /// 切换到下一张照片
  void _nextPhoto() {
    if (_photos.length <= 1) return;
    setState(() {
      final first = _photos.removeAt(0);
      _photos.add(first);
    });
  }

  Future<void> _removePhoto(String path) async {
    await PhotoWallService.removePhoto(path);
    _fetch();
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return AspectRatio(
        aspectRatio: 1,
        child: Center(
          child: Text(
            '加载中...',
            style: TextStyle(color: mutedText, fontSize: 14),
          ),
        ),
      );
    }

    if (_photos.isEmpty) {
      return GestureDetector(
        onTap: _addPhotos,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: hoverBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderColor,
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_rounded, color: tertiaryText, size: 28),
                  const SizedBox(height: 6),
                  Text('添加照片', style: TextStyle(color: tertiaryText, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _nextPhoto,
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(_photos.first),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06),
                    child: Icon(Icons.broken_image_outlined, color: isDark ? Colors.white30 : const Color(0xFFCCCCCC)),
                  ),
                ),
                // 悬停时显示添加和删除按钮
                if (_hovered)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _addPhotos,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _removePhoto(_photos.first),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
