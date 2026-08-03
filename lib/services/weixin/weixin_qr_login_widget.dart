/// QR 登录的 Flutter 组件（自研，脱离 weixin_clawbot 包）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'weixin_ilink_client.dart';
import 'weixin_models.dart';
import 'weixin_qr_login.dart';

/// 自包含的微信二维码绑定 UI。
///
/// 可嵌入任意页面或对话框，处理完整流程：
/// 获取二维码 → 展示 → 轮询 → 成功 / 过期。
///
/// ```dart
/// QrLoginWidget(
///   client: client,
///   onLoggedIn: (account) {
///     Navigator.of(context).pop();
///   },
/// )
/// ```
class QrLoginWidget extends StatefulWidget {
  /// 用于登录的 iLink 客户端（token 为空）。
  final WeixinILinkClient client;

  /// 登录成功时回调。
  final void Function(ClawBotAccount account)? onLoggedIn;

  /// 二维码过期时回调。
  final VoidCallback? onExpired;

  /// 渲染二维码的尺寸（逻辑像素）。
  final double qrSize;

  const QrLoginWidget({
    super.key,
    required this.client,
    this.onLoggedIn,
    this.onExpired,
    this.qrSize = 240,
  });

  @override
  State<QrLoginWidget> createState() => _QrLoginWidgetState();
}

class _QrLoginWidgetState extends State<QrLoginWidget> {
  _UiState _state = _Loading();
  StreamSubscription<QrLoginEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _startLogin();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startLogin() {
    setState(() => _state = _Loading());

    final flow = WeixinQrLoginFlow(client: widget.client);
    _sub?.cancel();
    _sub = flow.startLogin().listen(_onEvent, onError: _onError);
  }

  void _onEvent(QrLoginEvent event) {
    if (!mounted) return;
    // 延迟到 post-frame 回调，避免 Flutter Web 上的 pointer/mouse 帧断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (event) {
        case QrReadyEvent():
          setState(() => _state = _QrReady(event.qrContent));
        case QrScannedEvent():
          setState(() => _state = _Scanned());
        case QrConfirmedEvent():
          setState(() => _state = _Confirmed(event.account));
          widget.onLoggedIn?.call(event.account);
        case QrExpiredEvent():
          setState(() => _state = _Expired());
          widget.onExpired?.call();
        case QrErrorEvent():
          setState(() => _state = _Error(event.error.toString()));
      }
    });
  }

  void _onError(Object err) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _state = _Error(err.toString()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: widget.qrSize + 40,
      child: switch (_state) {
        _Loading() => SizedBox(
            height: widget.qrSize,
            child: const Center(child: CircularProgressIndicator.adaptive()),
          ),
        _QrReady(qrContent: final content) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '用微信扫码绑定 ClawBot',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _QrImageDisplay(content: content, size: widget.qrSize),
              const SizedBox(height: 12),
              Text(
                '打开微信 → 扫一扫',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        _Scanned() => const _StatusTile(
            icon: Icons.qr_code_scanner,
            label: '已扫码，请在手机上确认登录…',
            color: Colors.orange,
          ),
        _Confirmed(account: final account) => _StatusTile(
            icon: Icons.check_circle,
            label: '绑定成功！\nBot ID: ${account.botId}',
            color: Colors.green,
          ),
        _Expired() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _StatusTile(
                icon: Icons.timer_off,
                label: '二维码已过期',
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _startLogin,
                child: const Text('重新获取'),
              ),
            ],
          ),
        _Error(message: final msg) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusTile(
                icon: Icons.error_outline,
                label: '出错了：$msg',
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _startLogin,
                child: const Text('重试'),
              ),
            ],
          ),
      },
    );
  }
}

// ── 私有状态类型 ───────────────────────────────────────────────────────────

sealed class _UiState {}

final class _Loading extends _UiState {
  _Loading();
}

final class _QrReady extends _UiState {
  final String qrContent;
  _QrReady(this.qrContent);
}

final class _Scanned extends _UiState {
  _Scanned();
}

final class _Confirmed extends _UiState {
  final ClawBotAccount account;
  _Confirmed(this.account);
}

final class _Expired extends _UiState {
  _Expired();
}

final class _Error extends _UiState {
  final String message;
  _Error(this.message);
}

// ── QR 图片展示 ────────────────────────────────────────────────────────────

/// 展示 [content] 的二维码。
///
/// iLink API 返回的 `qrcode_img_content` 有两种形式：
///   1. base64 编码的 PNG 图片（服务器已预渲染二维码）
///   2. 客户端应编码为二维码的短文本/URL
///
/// 本组件自动检测并相应渲染。
class _QrImageDisplay extends StatelessWidget {
  final String content;
  final double size;

  const _QrImageDisplay({required this.content, required this.size});

  /// 若 [content] 是合法的 base64 编码 PNG/JPEG 则返回原始字节，否则返回 null。
  static Uint8List? _tryDecodeImage(String content) {
    try {
      // 去掉可能的 "data:image/...;base64," 前缀与空白/换行
      final raw = content.contains(',') ? content.split(',').last : content;
      final clean = raw.replaceAll(RegExp(r'\s+'), '');
      final bytes = base64Decode(clean);
      // PNG 魔数：89 50 4E 47；JPEG 魔数：FF D8 FF
      if (bytes.length > 4 &&
          ((bytes[0] == 0x89 &&
                  bytes[1] == 0x50 &&
                  bytes[2] == 0x4E &&
                  bytes[3] == 0x47) ||
              (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF))) {
        return bytes;
      }
    } catch (_) {
      // 不是合法 base64 → 落到文本渲染
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _tryDecodeImage(content);

    if (imageBytes != null) {
      // 服务器返回了预渲染的 QR PNG，直接展示。
      return Image.memory(
        imageBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, err, _) => _QrError(message: err.toString()),
      );
    }

    // 内容是 URL / 文本，客户端编码为二维码。
    return QrImageView(
      data: content,
      size: size,
      backgroundColor: Colors.white,
      errorStateBuilder: (_, err) =>
          _QrError(message: err?.toString() ?? 'QR 渲染失败'),
    );
  }
}

class _QrError extends StatelessWidget {
  final String message;
  const _QrError({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text(
            'QR 码渲染失败\n$message',
            style: const TextStyle(color: Colors.red, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── 辅助组件 ───────────────────────────────────────────────────────────────

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusTile({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

// ── 便捷对话框 ─────────────────────────────────────────────────────────────

/// 在 Material 对话框内展示 [QrLoginWidget]。
///
/// ```dart
/// final account = await showWeixinQrLoginDialog(
///   context: context,
///   client: client,
/// );
/// ```
Future<ClawBotAccount?> showWeixinQrLoginDialog({
  required BuildContext context,
  required WeixinILinkClient client,
}) {
  final completer = Completer<ClawBotAccount?>();

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('绑定微信 ClawBot'),
      content: QrLoginWidget(
        client: client,
        onLoggedIn: (account) {
          Navigator.of(ctx).pop();
          if (!completer.isCompleted) completer.complete(account);
        },
        onExpired: () {
          // Widget 自带重试按钮，不自动关闭。
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            if (!completer.isCompleted) completer.complete(null);
          },
          child: const Text('取消'),
        ),
      ],
    ),
  );

  return completer.future;
}
