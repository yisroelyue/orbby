/// 自研微信 iLink Bot API 数据模型（脱离 weixin_clawbot 包）。
///
/// 覆盖：账号、消息、getupdates 响应、发送结果、QR 登录响应。
library;

// ─── Login / QR Code ───────────────────────────────────────────────────────

/// 响应 `GET /ilink/bot/get_bot_qrcode`。
class QrCodeResponse {
  /// 不透明的 QR 码标识，用于轮询登录状态。
  final String qrCode;

  /// 应渲染为二维码的文本内容（用户用微信扫一扫）。
  final String qrCodeImgContent;

  const QrCodeResponse({required this.qrCode, required this.qrCodeImgContent});

  factory QrCodeResponse.fromJson(Map<String, dynamic> json) {
    return QrCodeResponse(
      qrCode: json['qrcode'] as String? ?? '',
      qrCodeImgContent: json['qrcode_img_content'] as String? ?? '',
    );
  }
}

/// QR 登录轮询过程中的状态。
enum QrLoginStatus {
  /// 等待用户扫码。
  wait,

  /// 用户已扫码，但尚未在手机上确认。
  scanned,

  /// 登录已确认，凭证可用。
  confirmed,

  /// 二维码已过期。
  expired,

  /// 未知或无法识别的状态字符串。
  unknown,
}

/// 响应 `GET /ilink/bot/get_qrcode_status`。
class QrStatusResponse {
  final QrLoginStatus status;

  /// 机器人的 Bearer token。当 [status] == [QrLoginStatus.confirmed] 时有值。
  final String? botToken;

  /// 机器人的 iLink 用户 ID。
  final String? ilinkBotId;

  /// 绑定用户（微信用户）的 iLink 用户 ID。
  final String? ilinkUserId;

  /// 服务器返回的 API base URL（可能不同于默认值）。
  final String? baseUrl;

  const QrStatusResponse({
    required this.status,
    this.botToken,
    this.ilinkBotId,
    this.ilinkUserId,
    this.baseUrl,
  });

  factory QrStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? '';
    final status = switch (rawStatus) {
      'wait' => QrLoginStatus.wait,
      'scaned' => QrLoginStatus.scanned,
      'confirmed' => QrLoginStatus.confirmed,
      'expired' => QrLoginStatus.expired,
      _ => QrLoginStatus.unknown,
    };

    return QrStatusResponse(
      status: status,
      botToken: json['bot_token'] as String?,
      ilinkBotId: json['ilink_bot_id'] as String?,
      ilinkUserId: json['ilink_user_id'] as String?,
      baseUrl: json['baseurl'] as String?,
    );
  }
}

// ─── Account ───────────────────────────────────────────────────────────────

/// 已持久化的机器人账号凭证。
///
/// 扫码登录成功后从服务器获得；用于所有 API 调用的鉴权。
class ClawBotAccount {
  /// 唯一账号标识，与 [botId] 相同。
  final String id;

  /// 用于 `Authorization` 头的 Bearer token。
  final String token;

  /// 服务器分配的 iLink API base URL。
  final String baseUrl;

  /// 机器人自身的 iLink 用户 ID，发送消息时作为 `from_user_id`。
  final String botId;

  /// 绑定用户的 iLink 用户 ID，主动发送时的默认 `toUserId`。
  final String? defaultTo;

  /// [defaultTo] 最近一次看到的 `context_token`。
  final String? contextToken;

  const ClawBotAccount({
    required this.id,
    required this.token,
    required this.baseUrl,
    required this.botId,
    this.defaultTo,
    this.contextToken,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'token': token,
    'baseUrl': baseUrl,
    'botId': botId,
    if (defaultTo != null) 'defaultTo': defaultTo,
    if (contextToken != null) 'contextToken': contextToken,
  };

  factory ClawBotAccount.fromJson(Map<String, dynamic> json) {
    return ClawBotAccount(
      id: json['id'] as String,
      token: json['token'] as String,
      baseUrl: json['baseUrl'] as String,
      botId: json['botId'] as String,
      defaultTo: json['defaultTo'] as String?,
      contextToken: json['contextToken'] as String?,
    );
  }

  ClawBotAccount copyWith({String? contextToken, String? defaultTo}) {
    return ClawBotAccount(
      id: id,
      token: token,
      baseUrl: baseUrl,
      botId: botId,
      defaultTo: defaultTo ?? this.defaultTo,
      contextToken: contextToken ?? this.contextToken,
    );
  }
}

// ─── Service status ─────────────────────────────────────────────────────────

enum WeixinConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// 可在多窗口之间传递的微信服务状态快照。
class WeixinServiceStatus {
  const WeixinServiceStatus({
    this.state = WeixinConnectionState.disconnected,
    this.enabled = false,
    this.hasAccount = false,
    this.botId = '',
    this.error,
  });

  final WeixinConnectionState state;
  final bool enabled;
  final bool hasAccount;
  final String botId;
  final String? error;

  bool get isConnected => state == WeixinConnectionState.connected;

  bool get isConnecting =>
      state == WeixinConnectionState.connecting ||
      state == WeixinConnectionState.reconnecting;

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'enabled': enabled,
    'hasAccount': hasAccount,
    'botId': botId,
    if (error != null && error!.isNotEmpty) 'error': error,
  };

  factory WeixinServiceStatus.fromJson(Map<String, dynamic> json) {
    final stateName = json['state'] as String?;
    final state = WeixinConnectionState.values.firstWhere(
      (value) => value.name == stateName,
      orElse: () => WeixinConnectionState.disconnected,
    );
    return WeixinServiceStatus(
      state: state,
      enabled: json['enabled'] as bool? ?? false,
      hasAccount: json['hasAccount'] as bool? ?? false,
      botId: json['botId'] as String? ?? '',
      error: json['error'] as String?,
    );
  }
}

// ─── Messages ──────────────────────────────────────────────────────────────

/// [MessageItem] 的类型区分器。
enum MessageItemType {
  text(1),
  image(2),
  voice(3),
  file(4),
  video(5),
  unknown(0);

  final int value;
  const MessageItemType(this.value);

  static MessageItemType fromInt(int v) => MessageItemType.values.firstWhere(
    (e) => e.value == v,
    orElse: () => MessageItemType.unknown,
  );
}

/// [WeixinMessage] 内部的一个内容段。
class MessageItem {
  final MessageItemType type;

  /// 当 [type] == [MessageItemType.text] 时有值。
  final String? text;

  /// 当 [type] == [MessageItemType.voice] 时有值（语音转文字结果）。
  final String? voiceText;

  /// 未支持类型的原始 JSON（图片、文件、视频）。
  final Map<String, dynamic>? raw;

  const MessageItem({required this.type, this.text, this.voiceText, this.raw});

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    final type = MessageItemType.fromInt(json['type'] as int? ?? 0);
    return MessageItem(
      type: type,
      text: (json['text_item'] as Map<String, dynamic>?)?['text'] as String?,
      voiceText:
          (json['voice_item'] as Map<String, dynamic>?)?['text'] as String?,
      raw: json,
    );
  }
}

/// 一条微信 iLink 消息（入站或出站）。
class WeixinMessage {
  final int seq;
  final int messageId;
  final String fromUserId;
  final String toUserId;
  final String clientId;

  /// Unix 毫秒时间戳。
  final int createTimeMs;

  /// 消息来源：`1` = 真实微信用户发送，`2` = 机器人发送。
  /// 使用便捷 getter [isFromUser] 而非直接比较。
  final int messageType;

  /// 流式状态：`0` = 新/完整，`1` = 生成中，`2` = 生成结束。
  final int messageState;

  /// 回复以触发微信通知所需的令牌。按发送者缓存，无需手动管理。
  final String? contextToken;

  /// 有序内容段列表。大多数消息只有一个元素。
  final List<MessageItem> items;

  const WeixinMessage({
    required this.seq,
    required this.messageId,
    required this.fromUserId,
    required this.toUserId,
    required this.clientId,
    required this.createTimeMs,
    required this.messageType,
    required this.messageState,
    this.contextToken,
    required this.items,
  });

  factory WeixinMessage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['item_list'] as List<dynamic>? ?? [];
    return WeixinMessage(
      seq: json['seq'] as int? ?? 0,
      messageId: json['message_id'] as int? ?? 0,
      fromUserId: json['from_user_id'] as String? ?? '',
      toUserId: json['to_user_id'] as String? ?? '',
      clientId: json['client_id'] as String? ?? '',
      createTimeMs: json['create_time_ms'] as int? ?? 0,
      messageType: json['message_type'] as int? ?? 0,
      messageState: json['message_state'] as int? ?? 0,
      contextToken: json['context_token'] as String?,
      items: rawItems
          .map((e) => MessageItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 返回 [items] 中第一条文本或语音转文字内容；无文本则返回 `null`。
  String? get textContent {
    for (final item in items) {
      if (item.type == MessageItemType.text && item.text != null) {
        return item.text;
      }
      if (item.type == MessageItemType.voice && item.voiceText != null) {
        return item.voiceText;
      }
    }
    return null;
  }

  /// `true` 表示消息由真实微信用户发送（`messageType == 1`）。
  bool get isFromUser => messageType == 1;
}

/// `POST /ilink/bot/getupdates` 长轮询响应。
class GetUpdatesResponse {
  final int ret;
  final int errCode;
  final String errMsg;
  final List<WeixinMessage> messages;
  final String getUpdatesBuf;
  final int longPollingTimeoutMs;

  const GetUpdatesResponse({
    required this.ret,
    required this.errCode,
    required this.errMsg,
    required this.messages,
    required this.getUpdatesBuf,
    required this.longPollingTimeoutMs,
  });

  bool get isOk => ret == 0 && errCode == 0;

  factory GetUpdatesResponse.fromJson(Map<String, dynamic> json) {
    final rawMsgs = json['msgs'] as List<dynamic>? ?? [];
    return GetUpdatesResponse(
      ret: json['ret'] as int? ?? 0,
      errCode: json['errcode'] as int? ?? 0,
      errMsg: json['errmsg'] as String? ?? '',
      messages: rawMsgs
          .map((e) => WeixinMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      getUpdatesBuf: json['get_updates_buf'] as String? ?? '',
      longPollingTimeoutMs: json['longpolling_timeout_ms'] as int? ?? 0,
    );
  }
}

// ─── Send result ───────────────────────────────────────────────────────────

/// 一次发送消息调用的结果。
class SendResult {
  final bool ok;
  final String to;
  final String clientId;
  final String? error;

  const SendResult({
    required this.ok,
    required this.to,
    required this.clientId,
    this.error,
  });

  @override
  String toString() =>
      ok ? 'SendResult(ok, to=$to)' : 'SendResult(error=$error)';
}
