/// 基于二维码的微信登录流程（自研，脱离 weixin_clawbot 包）。
library;

import 'dart:async';

import 'weixin_ilink_client.dart';
import 'weixin_models.dart';

/// QR 登录流程中发出的事件。
sealed class QrLoginEvent {}

/// 二维码已就绪。把 [qrContent] 渲染成二维码图片供用户用微信扫一扫。
final class QrReadyEvent extends QrLoginEvent {
  /// 需要编码为二维码的文本内容。
  final String qrContent;

  QrReadyEvent(this.qrContent);
}

/// 用户已扫码，但尚未在手机上点击"确认"。
final class QrScannedEvent extends QrLoginEvent {
  QrScannedEvent();
}

/// 登录成功。[account] 持有机器人凭证。
final class QrConfirmedEvent extends QrLoginEvent {
  final ClawBotAccount account;

  QrConfirmedEvent(this.account);
}

/// 二维码在用户扫码前过期。
final class QrExpiredEvent extends QrLoginEvent {
  QrExpiredEvent();
}

/// 登录流程中出现意外错误。
final class QrErrorEvent extends QrLoginEvent {
  final Object error;
  final StackTrace stackTrace;

  QrErrorEvent(this.error, this.stackTrace);
}

/// 驱动二维码微信登录握手。
///
/// 调用 [startLogin] 获得 [Stream] 的 [QrLoginEvent]。用
/// `qr_flutter` 的 `QrImageView` 展示 [QrReadyEvent.qrContent] 的二维码，
/// 然后等待 [QrConfirmedEvent] 或 [QrExpiredEvent]。
class WeixinQrLoginFlow {
  final WeixinILinkClient _client;

  /// 轮询扫码状态的间隔。
  final Duration pollInterval;

  /// 放弃前的总等待时间。
  final Duration loginTimeout;

  WeixinQrLoginFlow({
    required WeixinILinkClient client,
    this.pollInterval = const Duration(seconds: 2),
    this.loginTimeout = const Duration(minutes: 8),
  }) : _client = client;

  /// 开始登录握手，返回事件流。
  ///
  /// 在收到 [QrConfirmedEvent]、[QrExpiredEvent] 或 [QrErrorEvent] 后关闭。
  Stream<QrLoginEvent> startLogin() {
    final controller = StreamController<QrLoginEvent>();
    _runLogin(controller).then((_) {
      if (!controller.isClosed) controller.close();
    });
    return controller.stream;
  }

  Future<void> _runLogin(StreamController<QrLoginEvent> sink) async {
    try {
      // 第 1 步：获取二维码
      final qrResp = await _client.fetchLoginQrCode();
      if (qrResp.qrCodeImgContent.isEmpty) {
        sink.addError(Exception('服务端返回空的 qrcode_img_content'));
        return;
      }

      sink.add(QrReadyEvent(qrResp.qrCodeImgContent));

      // 第 2 步：轮询直到确认 / 过期 / 超时
      final deadline = DateTime.now().add(loginTimeout);

      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(pollInterval);

        final status = await _client.pollQrStatus(qrResp.qrCode);

        switch (status.status) {
          case QrLoginStatus.wait:
            // 继续轮询。
            break;

          case QrLoginStatus.scanned:
            sink.add(QrScannedEvent());

          case QrLoginStatus.confirmed:
            final token = status.botToken ?? '';
            final botId = status.ilinkBotId ?? '';
            if (token.isEmpty || botId.isEmpty) {
              sink.addError(
                Exception('登录确认但缺少 bot_token 或 ilink_bot_id'),
              );
              return;
            }
            final account = ClawBotAccount(
              id: botId,
              token: token,
              baseUrl: status.baseUrl?.isNotEmpty == true
                  ? status.baseUrl!
                  : _client.baseUrl,
              botId: botId,
              defaultTo: status.ilinkUserId,
            );
            sink.add(QrConfirmedEvent(account));
            return;

          case QrLoginStatus.expired:
            sink.add(QrExpiredEvent());
            return;

          case QrLoginStatus.unknown:
            // 忽略并继续轮询。
            break;
        }
      }

      // 超时
      sink.add(QrExpiredEvent());
    } catch (e, st) {
      sink.addError(e, st);
    }
  }
}
