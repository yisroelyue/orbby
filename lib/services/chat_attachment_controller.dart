import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';

import '../models/chat_attachment.dart';
import 'clipboard_image_service.dart';

/// 聊天附件状态：添加（去重/校验/缩略图）、删除、清空、发送 payload 编码、
/// 会话持久化拷贝。纯逻辑 ChangeNotifier，展示层（ChatAttachmentPreview）只读。
class ChatAttachmentController extends ChangeNotifier {
  ChatAttachmentController();

  /// 最多同时附 4 张
  static const maxCount = 4;

  /// 发送前最长边超过此值时缩放
  static const maxEdge = 4096;

  /// Base64 后单张上限（约对应原图 6MB）：超出时缩放/重编码
  static const maxPayloadBase64Bytes = 6 * 1024 * 1024;

  final _items = <ChatAttachment>[];

  /// id → sha256（内容去重，防止重复粘贴同一张图）
  final _hashes = <String, String>{};

  String? _transientError;
  Timer? _errorTimer;

  List<ChatAttachment> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  bool get hasUnready => _items.any((a) => !a.isReady);

  /// 短暂提示（第 5 张/超限/发送中粘贴等），预览区显示，几秒后自动消失
  String? get transientError => _transientError;

  /// 添加剪贴板读取结果。图片异步生成缩略图；文本/PDF 无需解码，直接就绪。
  /// 返回是否成功，失败时给出原因。
  Future<bool> add(ClipboardImageRead read) async {
    if (_items.length >= maxCount) {
      return _reject('最多添加 $maxCount 个附件');
    }
    final limit = ClipboardImageService.maxBytesForMime(read.attachment.mimeType);
    if (read.bytes.length > limit) {
      return _reject(
          '「${read.attachment.fileName}」超过 ${limit ~/ (1024 * 1024)} MB，无法添加');
    }
    final digest = sha256.convert(read.bytes).toString();
    if (_hashes.containsValue(digest)) {
      return _reject('该文件已在附件中');
    }
    final attachment = read.attachment;
    _items.add(attachment);
    _hashes[attachment.id] = digest;
    notifyListeners();

    if (!attachment.isImage) {
      attachment.status = ChatAttachmentStatus.ready;
      notifyListeners();
      return true;
    }

    try {
      final (width, height, thumbnail) =
          await ClipboardImageService.decodeMetaAndThumbnail(read.bytes);
      if (!_items.contains(attachment)) return false; // 等待期间被删除
      attachment
        ..width = width
        ..height = height
        ..thumbnailBytes = thumbnail
        ..status = ChatAttachmentStatus.ready;
    } catch (_) {
      if (!_items.contains(attachment)) return false;
      attachment.status = ChatAttachmentStatus.error;
    }
    notifyListeners();
    return true;
  }

  void remove(ChatAttachment attachment) {
    _items.remove(attachment);
    _hashes.remove(attachment.id);
    notifyListeners();
  }

  /// 清空全部附件（/clear、/new、切换会话时）
  void clear() {
    if (_items.isEmpty && _transientError == null) return;
    _items.clear();
    _hashes.clear();
    _transientError = null;
    _errorTimer?.cancel();
    notifyListeners();
  }

  void showHint(String message) => _showError(message);

  /// 取走全部就绪附件（转挂到即将发送的用户消息）；未就绪的继续留在列表。
  Future<List<ChatAttachment>> takeReady() async {
    // 先确保每张都完成 payload 编码（重载会话的附件也会在此补编码）
    for (final item in List.of(_items)) {
      if (item.isReady) await ensurePayload(item);
    }
    final ready = _items.where((a) => a.isReady).toList();
    for (final item in ready) {
      _items.remove(item);
      _hashes.remove(item.id);
    }
    notifyListeners();
    return ready;
  }

  /// 为附件生成发送 payload（含必要的缩放/重编码，跑在 isolate）。
  /// 结果缓存在 [ChatAttachment.sendPayload]，重复发送不再编码。
  static Future<void> ensurePayload(ChatAttachment item) async {
    if (item.sendPayload != null) return;
    final file = File(item.localPath);
    if (!await file.exists()) return; // 失效附件由发送流程剔除并提示
    final result = await compute(_encodeForPayload, {
      'path': item.localPath,
      'mimeType': item.mimeType,
      'maxEdge': maxEdge,
      'maxBase64': maxPayloadBase64Bytes,
    });
    item
      ..sendPayload = {
        'id': item.id,
        'fileName': item.fileName,
        'mimeType': result['mimeType'],
        'data': result['data'],
        if (result['width'] != null) 'width': result['width'],
        if (result['height'] != null) 'height': result['height'],
      }
      ..width = (result['width'] as num?)?.toInt() ?? item.width
      ..height = (result['height'] as num?)?.toInt() ?? item.height;
  }

  /// 把附件文件持久化到 ~/.orbby/attachments/{conversationId}/，
  /// 供会话重载后的缩略图展示与 /retry。已在目标目录的跳过。
  static Future<void> persistAll(
    String conversationId,
    List<ChatAttachment> attachments,
  ) async {
    if (attachments.isEmpty) return;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby/attachments/$conversationId');
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (_) {
      return; // 目录创建失败则放弃持久化，不阻塞发送
    }
    for (final item in attachments) {
      if (item.localPath.startsWith(dir.path)) continue;
      final ext = _extForFile(item);
      final target = '${dir.path}${Platform.pathSeparator}${item.id}.$ext';
      try {
        await File(item.localPath).copy(target);
        item.localPath = target;
      } catch (_) {
        // 复制失败保留原路径（临时文件通常仍可读）
      }
    }
  }

  void _showError(String message) {
    _transientError = message;
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      _transientError = null;
      notifyListeners();
    });
    notifyListeners();
  }

  bool _reject(String message) {
    _showError(message);
    return false;
  }
}

/// 持久化文件扩展名：优先保留原始扩展名（.md/.csv 等文本子类型对用户
/// 有意义），取不到再按 mime 兜底
String _extForFile(ChatAttachment item) {
  final name = item.fileName;
  if (name.contains('.')) {
    final ext = name.split('.').last.toLowerCase();
    if (ext.isNotEmpty) return ext;
  }
  return _extForMime(item.mimeType);
}

String _extForMime(String mimeType) => switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'application/pdf' => 'pdf',
      'text/plain' => 'txt',
      _ => 'png',
    };

/// isolate 入口：按需缩放/重编码并返回 Base64 payload。
/// 非图片附件（文本/PDF）不做任何转码原样透传；图片未超限的原样透传
/// （GIF 动画因此得以保留），超限时先缩放到 [maxEdge] 转 PNG，仍超限再转
/// JPEG（照片类内容 PNG 体积爆炸的兜底）。
Map<String, dynamic> _encodeForPayload(Map<String, dynamic> args) {
  final path = args['path'] as String;
  final mimeType = args['mimeType'] as String;
  final maxEdge = args['maxEdge'] as int;
  final maxBase64 = args['maxBase64'] as int;

  final bytes = File(path).readAsBytesSync();
  final data = base64Encode(bytes);
  if (!mimeType.startsWith('image/')) {
    return {'data': data, 'mimeType': mimeType};
  }
  if (data.length <= maxBase64) {
    return {'data': data, 'mimeType': mimeType};
  }

  // 长边信息未知（GIF/WebP 未解码），统一在重编码后回报真实尺寸
  final image = img.findDecoderForData(bytes)?.decode(bytes);
  if (image == null) {
    // 解不开的原样发送，交由服务端给出明确错误
    return {'data': data, 'mimeType': mimeType};
  }
  var resized = image;
  if (image.width > maxEdge || image.height > maxEdge) {
    final scale = maxEdge / (image.width > image.height ? image.width : image.height);
    resized = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
    );
  }
  var encoded = img.encodePng(resized);
  var result = base64Encode(encoded);
  if (result.length <= maxBase64) {
    return {
      'data': result,
      'mimeType': 'image/png',
      'width': resized.width,
      'height': resized.height,
    };
  }
  encoded = img.encodeJpg(resized, quality: 92);
  result = base64Encode(encoded);
  return {
    'data': result,
    'mimeType': 'image/jpeg',
    'width': resized.width,
    'height': resized.height,
  };
}
