import 'dart:typed_data';

/// 附件读取状态（仅内存态，不随会话落盘）
enum ChatAttachmentStatus { loading, ready, error }

/// 聊天图片附件：粘贴时产生，随用户消息进入会话。
/// 落盘 / 进 history 只存引用元数据（[toJson]）；Base64 仅在发送链路
/// 生成（[toPayload]），绝不写入会话 JSON。
class ChatAttachment {
  ChatAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.localPath,
    this.thumbnailBytes,
    this.width,
    this.height,
    this.sizeBytes = 0,
    this.status = ChatAttachmentStatus.ready,
  });

  final String id;
  final String fileName;

  /// image/png | image/jpeg | image/webp | image/gif |
  /// text/plain（文本类统一值，真实类型看扩展名）| application/pdf
  final String mimeType;

  /// 是否图片附件：决定缩略图解码、预览/查看器形态与发送编码路径
  bool get isImage => mimeType.startsWith('image/');

  /// 本地可读路径；截图粘贴为临时 PNG，发送/落盘前会持久化到
  /// ~/.orbby/attachments/{conversationId}/
  String localPath;

  /// 预览缩略图（内存态，最大宽 320px；重载会话时为空，走 Image.file）
  Uint8List? thumbnailBytes;
  int? width;
  int? height;
  int sizeBytes;
  ChatAttachmentStatus status;

  /// 发送 payload 缓存（由 ChatAttachmentController.ensurePayload 填充，仅
  /// 内存态）：重编码后 mimeType/尺寸可能变化，故缓存整份 payload。
  /// null = 尚未编码。
  Map<String, dynamic>? sendPayload;

  bool get isReady => status == ChatAttachmentStatus.ready;

  /// 会话落盘 / 消息展示用的引用元数据：不含缩略图与 Base64
  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'mimeType': mimeType,
        'localPath': localPath,
        'width': width,
        'height': height,
        'sizeBytes': sizeBytes,
      };

  /// 重载会话：只恢复引用；缩略图不落盘，展示时直接读 localPath
  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        id: json['id']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? 'image.png',
        mimeType: json['mimeType']?.toString() ?? 'image/png',
        localPath: json['localPath']?.toString() ?? '',
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}
