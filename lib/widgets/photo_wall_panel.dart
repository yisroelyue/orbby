import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
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

  // 堆叠显示的最大照片数量
  static const int _maxStack = 4;

  @override
  EdgeInsetsGeometry get panelPadding => const EdgeInsets.all(12);

  @override
  BoxDecoration? get panelDecoration => const BoxDecoration(
        color: Colors.transparent,
      );

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);
    if (!PanelCache.has('photo_wall_photos')) {
      setState(() => _loading = true);
      PanelDataService.refreshPhotoWall();
    }
    _startShuffleTimer();
  }

  void _startShuffleTimer() async {
    final settings = await SettingsService.load();
    final interval = settings.photoWallSwitchInterval;
    _shuffleTimer?.cancel();
    _shuffleTimer = Timer.periodic(
      Duration(seconds: interval),
      (_) => _nextPhoto(),
    );
  }

  @override
  void dispose() {
    PanelCache.removeListener(_onCacheChanged);
    _shuffleTimer?.cancel();
    super.dispose();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<List<String>>('photo_wall_photos');
    if (cached != null && mounted) {
      setState(() {
        _photos = List<String>.from(cached)..shuffle();
        _loading = false;
      });
    }
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
    PanelDataService.refreshPhotoWall();
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
    PanelDataService.refreshPhotoWall();
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: _buildStack(key: ValueKey(_photos.first)),
          ),
        ),
      ),
    );
  }

  Widget _buildStack({Key? key}) {
    final stackSize = min(_photos.length, _maxStack);
    // 每层偏移量
    const dx = 10.0;
    const dy = 8.0;

    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 从底层到顶层渲染（index=0 是最底层）
              ...List.generate(stackSize, (index) {
                final isTop = index == stackSize - 1;
                final layer = index; // 0=底层, stackSize-1=顶层
                final distanceFromTop = stackSize - 1 - layer;
                final rotation = layer * 0.02;

                // 底层向右下偏移，顶层在左上角
                final left = distanceFromTop * dx;
                final top = distanceFromTop * dy;
                final cardW = w - (stackSize - 1) * dx;
                final cardH = h - (stackSize - 1) * dy;

                return Positioned(
                  left: left,
                  top: top,
                  width: cardW,
                  height: cardH,
                  child: Transform.rotate(
                    angle: isTop ? 0 : (layer.isOdd ? rotation : -rotation),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isTop ? 0.4 : 0.15),
                            blurRadius: isTop ? 16 : 6,
                            offset: Offset(0, isTop ? 6 : 3),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Image.file(
                            File(_photos[stackSize - 1 - index]),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.06),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: isDark ? Colors.white30 : const Color(0xFFCCCCCC),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
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
          );
        },
      ),
    );
  }
}
