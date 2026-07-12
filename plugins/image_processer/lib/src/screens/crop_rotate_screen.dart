import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';

class CropRotateScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final ui.Image? loadedImage;
  final String outputDir;
  final void Function(String) onStatusUpdate;
  final Future<void> Function(Future<bool> Function()) onProcess;

  const CropRotateScreen({
    super.key,
    required this.imagePath,
    required this.imageBytes,
    required this.loadedImage,
    required this.outputDir,
    required this.onStatusUpdate,
    required this.onProcess,
  });

  @override
  State<CropRotateScreen> createState() => _CropRotateScreenState();
}

class _CropRotateScreenState extends State<CropRotateScreen> {
  double _rotation = 0;
  bool _flipH = false;
  bool _flipV = false;

  double _cropLeft = 0, _cropTop = 0, _cropWidth = 0, _cropHeight = 0;
  bool _cropInitialized = false;

  int? _draggingHandle;
  Offset? _lastDragPos;

  static const double _handleSize = 12;
  static const double _minCropSize = 20;
  static const double _previewPadding = 20;

  @override
  void initState() {
    super.initState();
    _initCrop();
  }

  @override
  void didUpdateWidget(covariant CropRotateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadedImage != oldWidget.loadedImage) {
      _initCrop();
    }
  }

  void _initCrop() {
    if (widget.loadedImage == null) return;
    _cropLeft = 0;
    _cropTop = 0;
    _cropWidth = widget.loadedImage!.width.toDouble();
    _cropHeight = widget.loadedImage!.height.toDouble();
    _cropInitialized = true;
    _rotation = 0;
    _flipH = false;
    _flipV = false;
    setState(() {});
  }

  void _resetCrop() => _initCrop();

  void _resetAngle() {
    setState(() {
      _rotation = 0;
      _flipH = false;
      _flipV = false;
    });
  }

  double _normalizeRotation(double value) {
    var normalized = value % 360;
    if (normalized > 180) normalized -= 360;
    if (normalized < -180) normalized += 360;
    return normalized;
  }

  void _rotateLeft90() =>
      setState(() => _rotation = _normalizeRotation(_rotation - 90));
  void _rotateRight90() =>
      setState(() => _rotation = _normalizeRotation(_rotation + 90));

  int _findHandle(
    Offset localPos,
    double imgL,
    double imgT,
    double imgW,
    double imgH,
  ) {
    final handles = [
      Offset(imgL, imgT),
      Offset(imgL + imgW / 2, imgT),
      Offset(imgL + imgW, imgT),
      Offset(imgL, imgT + imgH / 2),
      Offset(imgL + imgW, imgT + imgH / 2),
      Offset(imgL, imgT + imgH),
      Offset(imgL + imgW / 2, imgT + imgH),
      Offset(imgL + imgW, imgT + imgH),
    ];
    final handleRadius = _handleSize;
    for (int i = 0; i < handles.length; i++) {
      if ((localPos - handles[i]).distance < handleRadius * 2) return i;
    }
    return -1;
  }

  bool _isInsideCrop(Offset p, double l, double t, double w, double h) {
    return p.dx >= l && p.dx <= l + w && p.dy >= t && p.dy <= t + h;
  }

  void _onPanStart(DragStartDetails details, double cw, double ch) {
    if (widget.loadedImage == null || !_cropInitialized) return;
    final iw = widget.loadedImage!.width.toDouble();
    final ih = widget.loadedImage!.height.toDouble();
    final scale = _calcScale(cw, ch, iw, ih);
    final dw = iw * scale;
    final dh = ih * scale;
    final dl = (cw - dw) / 2;
    final dt = (ch - dh) / 2;
    final cropDisplayLeft = dl + _cropLeft * scale;
    final cropDisplayTop = dt + _cropTop * scale;
    final cropDisplayWidth = _cropWidth * scale;
    final cropDisplayHeight = _cropHeight * scale;
    final pos = details.localPosition;
    final handle = _findHandle(
      pos,
      cropDisplayLeft,
      cropDisplayTop,
      cropDisplayWidth,
      cropDisplayHeight,
    );
    if (handle >= 0) {
      _draggingHandle = handle;
      _lastDragPos = pos;
      return;
    }
    if (_isInsideCrop(
      pos,
      cropDisplayLeft,
      cropDisplayTop,
      cropDisplayWidth,
      cropDisplayHeight,
    )) {
      _draggingHandle = -1;
      _lastDragPos = pos;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, double cw, double ch) {
    if (_draggingHandle == null || widget.loadedImage == null) return;
    final iw = widget.loadedImage!.width.toDouble();
    final ih = widget.loadedImage!.height.toDouble();
    final scale = _calcScale(cw, ch, iw, ih);
    final dx =
        (details.localPosition.dx -
            (_lastDragPos?.dx ?? details.localPosition.dx)) /
        scale;
    final dy =
        (details.localPosition.dy -
            (_lastDragPos?.dy ?? details.localPosition.dy)) /
        scale;
    _lastDragPos = details.localPosition;

    if (_draggingHandle == -1) {
      setState(() {
        _cropLeft = (_cropLeft + dx).clamp(0.0, iw - _cropWidth);
        _cropTop = (_cropTop + dy).clamp(0.0, ih - _cropHeight);
      });
      return;
    }

    double nl = _cropLeft,
        nt = _cropTop,
        nr = _cropLeft + _cropWidth,
        nb = _cropTop + _cropHeight;
    switch (_draggingHandle) {
      case 0:
        nl += dx; nt += dy;
      case 1:
        nt += dy;
      case 2:
        nr += dx; nt += dy;
      case 3:
        nl += dx;
      case 4:
        nr += dx;
      case 5:
        nl += dx; nb += dy;
      case 6:
        nb += dy;
      case 7:
        nr += dx; nb += dy;
    }

    final handle = _draggingHandle!;
    final adjustsLeft = handle == 0 || handle == 3 || handle == 5;
    final adjustsRight = handle == 2 || handle == 4 || handle == 7;
    final adjustsTop = handle == 0 || handle == 1 || handle == 2;
    final adjustsBottom = handle == 5 || handle == 6 || handle == 7;

    if (!adjustsLeft) nl = _cropLeft;
    if (!adjustsRight) nr = _cropLeft + _cropWidth;
    if (!adjustsTop) nt = _cropTop;
    if (!adjustsBottom) nb = _cropTop + _cropHeight;

    if (adjustsLeft) nl = nl.clamp(0.0, nr - _minCropSize);
    if (adjustsRight) nr = nr.clamp(nl + _minCropSize, iw);
    if (adjustsTop) nt = nt.clamp(0.0, nb - _minCropSize);
    if (adjustsBottom) nb = nb.clamp(nt + _minCropSize, ih);

    setState(() {
      _cropLeft = nl;
      _cropTop = nt;
      _cropWidth = nr - nl;
      _cropHeight = nb - nt;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _draggingHandle = null;
    _lastDragPos = null;
  }

  double _calcScale(double cw, double ch, double iw, double ih) {
    final aw = math.max(1.0, cw - _previewPadding * 2);
    final ah = math.max(1.0, ch - _previewPadding * 2);
    return math.min(aw / iw, ah / ih);
  }

  Future<bool> _doProcess() async {
    if (widget.imagePath == null) return false;
    try {
      final result = await ImageProcessor.cropRotate(
        inputPath: widget.imagePath!,
        outputDir: widget.outputDir,
        cropRect: CropRect(
          x: _cropLeft.round(),
          y: _cropTop.round(),
          width: _cropWidth.round(),
          height: _cropHeight.round(),
        ),
        rotation: _rotation,
        flipH: _flipH,
        flipV: _flipV,
      );
      widget.onStatusUpdate('裁剪旋转完成: ${result.width}×${result.height}');
      return true;
    } catch (e) {
      widget.onStatusUpdate('处理失败: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.loadedImage != null && _cropInitialized;
    return ExcludeSemantics(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Image preview
        Expanded(
          flex: 6,
          child: Container(
            color: const Color(0xFF2A2A2A),
            child: hasImage
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = _calcScale(
                        constraints.maxWidth,
                        constraints.maxHeight,
                        widget.loadedImage!.width.toDouble(),
                        widget.loadedImage!.height.toDouble(),
                      );
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => _onPanStart(
                          d,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        onPanUpdate: (d) => _onPanUpdate(
                          d,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        onPanEnd: _onPanEnd,
                        child: CustomPaint(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          painter: _CropOverlayPainter(
                            image: widget.loadedImage!,
                            cropLeft: _cropLeft,
                            cropTop: _cropTop,
                            cropWidth: _cropWidth,
                            cropHeight: _cropHeight,
                            rotation: _rotation,
                            flipH: _flipH,
                            flipV: _flipV,
                            scale: scale,
                          ),
                        ),
                      );
                    },
                  )
                : const Center(
                    child: Text('请选择图片', style: TextStyle(color: Color(0xFF757575))),
                  ),
          ),
        ),
        // Right: Configuration panel
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              left: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '旋转角度:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_rotation.round()}°',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.rotate_left),
                      tooltip: '向左旋转90°',
                      onPressed: hasImage ? _rotateLeft90 : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.rotate_right),
                      tooltip: '向右旋转90°',
                      onPressed: hasImage ? _rotateRight90 : null,
                    ),
                  ],
                ),
                Slider(
                  value: _rotation,
                  min: -180,
                  max: 180,
                  divisions: 72,
                  label: '${_rotation.round()}°',
                  onChanged: hasImage
                      ? (v) => setState(() => _rotation = v)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [-180, -135, -90, -45, 0, 45, 90, 135, 180]
                        .map(
                          (d) => Text(
                            '$d°',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.grey,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '翻转:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: const Text('水平翻转'),
                      selected: _flipH,
                      onSelected: hasImage
                          ? (v) => setState(() => _flipH = v)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('垂直翻转'),
                      selected: _flipV,
                      onSelected: hasImage
                          ? (v) => setState(() => _flipV = v)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: hasImage ? _resetCrop : null,
                      child: const Text('重置裁剪'),
                    ),
                    TextButton(
                      onPressed: hasImage ? _resetAngle : null,
                      child: const Text('重置角度'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (hasImage)
                  Text(
                    '裁剪: 左${_cropLeft.round()} 上${_cropTop.round()} 右${(widget.loadedImage!.width - _cropLeft - _cropWidth).round()} 下${(widget.loadedImage!.height - _cropTop - _cropHeight).round()} | 结果: ${_cropWidth.round()}×${_cropHeight.round()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: hasImage
                      ? () => widget.onProcess(_doProcess)
                      : null,
                  icon: const Icon(Icons.crop),
                  label: const Text('开始处理'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ));
  }
}

class _CropOverlayPainter extends CustomPainter {
  final ui.Image image;
  final double cropLeft, cropTop, cropWidth, cropHeight;
  final double rotation;
  final bool flipH, flipV;
  final double scale;

  _CropOverlayPainter({
    required this.image,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    required this.rotation,
    required this.flipH,
    required this.flipV,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final dw = iw * scale;
    final dh = ih * scale;
    final ox = (size.width - dw) / 2;
    final oy = (size.height - dh) / 2;

    canvas.save();
    canvas.translate(ox + dw / 2, oy + dh / 2);
    if (flipH) canvas.scale(-1, 1);
    if (flipV) canvas.scale(1, -1);
    if (rotation != 0) canvas.rotate(rotation * math.pi / 180);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromCenter(center: Offset.zero, width: dw, height: dh),
      Paint(),
    );
    canvas.restore();

    final cdL = ox + cropLeft * scale;
    final cdT = oy + cropTop * scale;
    final cdW = cropWidth * scale;
    final cdH = cropHeight * scale;
    final cr = Rect.fromLTWH(cdL, cdT, cdW, cdH);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cr)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.5));

    final gridP = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 3; i++) {
      final x = cdL + cdW * i / 3;
      final y = cdT + cdH * i / 3;
      canvas.drawLine(Offset(x, cdT), Offset(x, cdT + cdH), gridP);
      canvas.drawLine(Offset(cdL, y), Offset(cdL + cdW, y), gridP);
    }

    canvas.drawRect(
      cr,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    final hFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final hStroke = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final handles = [
      Offset(cdL, cdT),
      Offset(cdL + cdW / 2, cdT),
      Offset(cdL + cdW, cdT),
      Offset(cdL, cdT + cdH / 2),
      Offset(cdL + cdW, cdT + cdH / 2),
      Offset(cdL, cdT + cdH),
      Offset(cdL + cdW / 2, cdT + cdH),
      Offset(cdL + cdW, cdT + cdH),
    ];
    for (final pos in handles) {
      final r = Rect.fromCenter(center: pos, width: 12, height: 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        hFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        hStroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => true;
}
