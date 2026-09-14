import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../models/chat_attachment.dart';

/// 剪贴板图片读取结果：附件对象 + 原始字节（去重 / 缩略图用）
class ClipboardImageRead {
  const ClipboardImageRead({required this.attachment, required this.bytes});

  final ChatAttachment attachment;
  final Uint8List bytes;
}

/// 剪贴板附件读取结果：read=支持的附件；unsupportedFileName=剪贴板里是
/// 文件但类型不支持（调用方提示后仍回退文本粘贴）。两者皆空=无附件可粘贴。
class ClipboardImageReadResult {
  const ClipboardImageReadResult({this.read, this.unsupportedFileName});

  final ClipboardImageRead? read;
  final String? unsupportedFileName;
}

/// Windows 剪贴板附件读取：原生通道（CF_HDROP / CF_DIBV5 / CF_DIB / CF_BITMAP）。
/// 资源管理器复制的图片/文本/PDF 文件直接引用原路径；截图等位图数据由原生写成
/// PNG 临时文件。仅 menu 窗口 engine 内使用（channel 在该 engine 注册）。
class ClipboardImageService {
  ClipboardImageService._();

  static const _channel = MethodChannel('orbby_clipboard_image');

  /// 支持的附件 mime 白名单（与 LLM 端一致；bmp 在原生层放行但此处不收）
  static const supportedMimeTypes = {
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
    'text/plain',
    'application/pdf',
  };

  /// 按类型取原文件大小上限：图片 10MB / 文本 5MB / PDF 20MB
  static int maxBytesForMime(String mimeType) => switch (mimeType) {
        'application/pdf' => 20 * 1024 * 1024,
        'text/plain' => 5 * 1024 * 1024,
        _ => 10 * 1024 * 1024,
      };

  /// 读取剪贴板附件（图片/文本/PDF）。
  /// [ClipboardImageReadResult.read] = 支持的附件；[ClipboardImageReadResult.unsupportedFileName]
  /// = 剪贴板里是文件但类型不支持（供调用方提示，仍会回退文本粘贴）。
  /// 通道异常向上抛出，由调用方按"无附件"处理。
  static Future<ClipboardImageReadResult> readFromClipboard() async {
    final raw = await _channel.invokeMethod('readImage');
    if (raw == null) return const ClipboardImageReadResult();
    final data = Map<String, dynamic>.from(raw as Map);
    final kind = data['kind'] as String?;
    final path = data['path'] as String? ?? '';
    if (path.isEmpty) return const ClipboardImageReadResult();

    if (kind == 'file') {
      final mime = mimeFromPath(path);
      // 不支持的文件按"无附件"处理，交回普通文本粘贴
      if (mime == null || !supportedMimeTypes.contains(mime)) {
        return ClipboardImageReadResult(unsupportedFileName: _fileNameFromPath(path));
      }
      return ClipboardImageReadResult(read: await _readFile(path, mime));
    }
    if (kind == 'bitmap') {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      return ClipboardImageReadResult(
          read: await _readFile(path, 'image/png', fileName: 'clipboard-$stamp.png'));
    }
    if (kind == 'file-unsupported') {
      return ClipboardImageReadResult(unsupportedFileName: _fileNameFromPath(path));
    }
    return const ClipboardImageReadResult();
  }

  static String _fileNameFromPath(String path) =>
      path.split(Platform.pathSeparator).last;

  /// 按扩展名推断附件 mime；不支持的类型返回 null。
  /// 文本类（代码/配置/标记语言）统一记为 text/plain，真实类型由文件名体现。
  static String? mimeFromPath(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      'txt' || 'md' || 'markdown' || 'csv' || 'log' || 'json' || 'yaml' ||
      'yml' || 'xml' || 'html' || 'htm' || 'dart' || 'js' || 'ts' || 'py' ||
      'java' || 'kt' || 'c' || 'h' || 'cpp' || 'cs' || 'go' || 'rs' || 'sh' ||
      'bat' || 'ini' || 'cfg' =>
        'text/plain',
      _ => null,
    };
  }

  static Future<ClipboardImageRead> _readFile(
    String path,
    String mimeType, {
    String? fileName,
  }) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final name = fileName ??
        path.split(Platform.pathSeparator).last;
    final attachment = ChatAttachment(
      id: 'att-${DateTime.now().microsecondsSinceEpoch}',
      fileName: name.isEmpty ? 'image.png' : name,
      mimeType: mimeType,
      localPath: path,
      sizeBytes: bytes.length,
      status: ChatAttachmentStatus.loading,
    );
    // 原生已带回尺寸的 bitmap 分支直接使用，file 分支惰性由缩略图解码补全
    return ClipboardImageRead(attachment: attachment, bytes: bytes);
  }

  /// 解码图片元信息并生成缩略图（最大宽 320 的 PNG）。
  /// dart:ui 解码只能跑在主 isolate（异步不阻塞 UI），勿挪进 compute。
  static Future<(int width, int height, Uint8List? thumbnail)> decodeMetaAndThumbnail(
    Uint8List bytes,
  ) async {
    final full = await ui.instantiateImageCodec(bytes);
    final frame = await full.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    full.dispose();

    Uint8List? thumbnail;
    final targetWidth = width > 320 ? 320 : width;
    final thumbCodec =
        await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final thumbFrame = await thumbCodec.getNextFrame();
    thumbnail =
        (await thumbFrame.image.toByteData(format: ui.ImageByteFormat.png))
            ?.buffer
            .asUint8List();
    thumbFrame.image.dispose();
    thumbCodec.dispose();
    return (width, height, thumbnail);
  }
}
