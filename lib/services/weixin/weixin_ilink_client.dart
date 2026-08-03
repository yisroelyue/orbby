import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../log_service.dart';
import 'weixin_models.dart';

/// 自定义 iLink Bot API 客户端（自研，不依赖 weixin_clawbot 包）。
///
/// 要点：
/// - `X-WECHAT-UIN` 每个客户端实例固定生成一次，跨请求保持不变。
///   服务端用 UIN 追踪会话，若每次请求随机生成会返回 `errcode=-14
///   session timeout`。
/// - 带 `iLink-App-Id` / `iLink-App-ClientVersion` 请求头。
/// - getupdates 长轮询具备指数退避重试（1s → 30s 上限）。
class WeixinILinkClient {
  WeixinILinkClient({
    required this.token,
    this.botId = '',
    String? baseUrl,
    http.Client? httpClient,
  }) : baseUrl = (baseUrl ?? 'https://ilinkai.weixin.qq.com').replaceAll(
         RegExp(r'/+$'),
         '',
       ),
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final String token;

  /// 机器人自身 ID，发送消息时作为 `from_user_id`。
  final String botId;

  final http.Client _http;

  /// 全局递增的实例 ID，用于日志区分多个客户端。
  static int _nextInstanceId = 0;
  final int _instanceId = ++_nextInstanceId;

  /// 固定的 session UIN（每个客户端实例生成一次）
  final String _wechatUin = _generateWechatUin();

  String _updatesBuf = '';
  bool _running = false;

  /// 轮询循环代际：每次 startPolling 递增；旧循环发现代际不符立即退出，
  /// 防止 stopPolling/startPolling 竞态产生多个并发循环。
  int _loopGeneration = 0;

  int _consecutiveErrors = 0;
  static const _maxBackoffSeconds = 30;
  bool _reportedConnected = false;
  void Function()? _onConnected;
  void Function(Object error)? _onConnectionError;

  StreamController<WeixinMessage>? _controller;

  // -------------------------------------------------------------------------
  // QR 登录
  // -------------------------------------------------------------------------

  /// 获取登录二维码（bot_type=3 为标准 ClawBot 类型）。
  Future<QrCodeResponse> fetchLoginQrCode() async {
    final uri = Uri.parse('$baseUrl/ilink/bot/get_bot_qrcode?bot_type=3');
    final resp = await _http.get(uri);
    _assertHttpOk(resp, 'get_bot_qrcode');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return QrCodeResponse.fromJson(json);
  }

  /// 轮询登录状态。
  Future<QrStatusResponse> pollQrStatus(String qrCode) async {
    final encoded = Uri.encodeComponent(qrCode);
    final uri = Uri.parse(
      '$baseUrl/ilink/bot/get_qrcode_status?qrcode=$encoded',
    );
    final resp = await _http.get(
      uri,
      headers: {'iLink-App-ClientVersion': '1'},
    );
    _assertHttpOk(resp, 'get_qrcode_status');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return QrStatusResponse.fromJson(json);
  }

  // -------------------------------------------------------------------------
  // 长轮询
  // -------------------------------------------------------------------------

  /// 启动长轮询消息流。
  Stream<WeixinMessage> startPolling({
    void Function()? onConnected,
    void Function(Object error)? onConnectionError,
  }) {
    if (_running) return _controller!.stream;
    _running = true;
    _consecutiveErrors = 0;
    _reportedConnected = false;
    _onConnected = onConnected;
    _onConnectionError = onConnectionError;
    final gen = ++_loopGeneration;
    _controller = StreamController<WeixinMessage>.broadcast(
      onCancel: stopPolling,
    );
    _pollLoop(gen);
    return _controller!.stream;
  }

  void stopPolling() {
    if (!_running && _controller == null) return;
    _running = false;
    _loopGeneration++;
    final controller = _controller;
    _controller = null;
    _onConnected = null;
    _onConnectionError = null;
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  Future<void> _pollLoop(int gen) async {
    Duration pollTimeout = const Duration(seconds: 35);

    while (_running && gen == _loopGeneration) {
      try {
        final resp = await _getUpdates(timeout: pollTimeout);

        if (!_running || gen != _loopGeneration) break;

        if (resp.longPollingTimeoutMs > 0) {
          pollTimeout = Duration(milliseconds: resp.longPollingTimeoutMs);
        }

        if (!resp.isOk) {
          final error = Exception(
            'getupdates ret=${resp.ret} errcode=${resp.errCode} '
            '${resp.errMsg}',
          );
          LogService.warn(
            'WeixinILinkClient[$_instanceId]: getupdates error '
            'url=$baseUrl/ilink/bot/getupdates ret=${resp.ret} '
            'errcode=${resp.errCode} ${resp.errMsg}',
            category: 'weixin',
          );
          _reportedConnected = false;
          _onConnectionError?.call(error);
          if (!_running || gen != _loopGeneration) break;
          await _backoffDelay();
          continue;
        }

        // 成功响应 → 重置错误计数
        _consecutiveErrors = 0;
        if (!_reportedConnected) {
          _reportedConnected = true;
          _onConnected?.call();
        }

        if (resp.getUpdatesBuf.isNotEmpty &&
            resp.getUpdatesBuf != _updatesBuf) {
          _updatesBuf = resp.getUpdatesBuf;
        }

        for (final msg in resp.messages) {
          if (!(_controller?.isClosed ?? true)) {
            _controller!.add(msg);
          }
        }
      } catch (e) {
        if (!_running || gen != _loopGeneration) break;
        LogService.warn('WeixinILinkClient[$_instanceId]: poll error – $e', category: 'weixin');
        _reportedConnected = false;
        _onConnectionError?.call(e);
        if (!_running || gen != _loopGeneration) break;
        await _backoffDelay();
      }
    }
  }

  /// 指数退避：1s → 2s → 4s → 8s → 16s → 30s（上限）
  Future<void> _backoffDelay() async {
    _consecutiveErrors++;
    final seconds = (_consecutiveErrors <= 5)
        ? (1 << (_consecutiveErrors - 1))
        : _maxBackoffSeconds;
    LogService.info(
      'WeixinILinkClient[$_instanceId]: 退避 ${seconds}s（连续错误 $_consecutiveErrors 次）',
      category: 'weixin',
    );
    await Future.delayed(Duration(seconds: seconds));
  }

  Future<GetUpdatesResponse> _getUpdates({required Duration timeout}) async {
    final body = jsonEncode({
      'get_updates_buf': _updatesBuf,
      'base_info': {'channel_version': '2.4.3'},
    });

    final uri = Uri.parse('$baseUrl/ilink/bot/getupdates');
    final resp = await _http
        .post(uri, headers: _headers(body), body: body)
        .timeout(timeout + const Duration(seconds: 5));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('getupdates HTTP ${resp.statusCode}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return GetUpdatesResponse.fromJson(json);
  }

  // -------------------------------------------------------------------------
  // 发送消息
  // -------------------------------------------------------------------------

  Future<SendResult> sendText({
    required String toUserId,
    required String text,
    String? contextToken,
  }) async {
    final clientId = 'flutter-${DateTime.now().microsecondsSinceEpoch}';
    final body = jsonEncode({
      'msg': {
        'from_user_id': botId,
        'to_user_id': toUserId,
        'client_id': clientId,
        'message_type': 2,
        'message_state': 2,
        'context_token': ?contextToken,
        'item_list': [
          {
            'type': 1,
            'text_item': {'text': text},
          },
        ],
      },
      'base_info': {'channel_version': '2.4.3'},
    });

    final uri = Uri.parse('$baseUrl/ilink/bot/sendmessage');
    try {
      final resp = await _http
          .post(uri, headers: _headers(body), body: body)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return SendResult(
          ok: false,
          to: toUserId,
          clientId: clientId,
          error: 'HTTP ${resp.statusCode}',
        );
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final ret = json['ret'] as int? ?? 0;
      if (ret != 0) {
        return SendResult(
          ok: false,
          to: toUserId,
          clientId: clientId,
          error: 'ret=$ret',
        );
      }
      return SendResult(ok: true, to: toUserId, clientId: clientId);
    } catch (e) {
      return SendResult(
        ok: false,
        to: toUserId,
        clientId: clientId,
        error: '$e',
      );
    }
  }

  // -------------------------------------------------------------------------
  // HTTP headers（关键：固定 UIN + iLink-App-Id / iLink-App-ClientVersion）
  // -------------------------------------------------------------------------

  Map<String, String> _headers(String body) {
    return <String, String>{
      'Content-Type': 'application/json',
      'AuthorizationType': 'ilink_bot_token',
      'Content-Length': utf8.encode(body).length.toString(),
      'X-WECHAT-UIN': _wechatUin,
      'iLink-App-Id': 'bot',
      'iLink-App-ClientVersion': '132099',
      'Authorization': 'Bearer $token',
    };
  }

  static String _generateWechatUin() {
    final rng = Random.secure();
    final bytes = Uint8List(4)
      ..[0] = rng.nextInt(256)
      ..[1] = rng.nextInt(256)
      ..[2] = rng.nextInt(256)
      ..[3] = rng.nextInt(256);
    final number =
        (bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]) >>> 0;
    return base64.encode(utf8.encode(number.toString()));
  }

  static void _assertHttpOk(http.Response resp, String endpoint) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('$endpoint HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  void dispose() {
    stopPolling();
    _http.close();
  }
}
