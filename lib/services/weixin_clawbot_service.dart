import 'dart:async';

import 'package:flutter/material.dart';

import 'agent_service.dart';
import 'log_service.dart';
import 'weixin_account_store.dart';
import 'weixin_ilink_client.dart';
import 'weixin_models.dart';
import 'weixin_qr_login_widget.dart';

/// 微信 Clawbot 服务（自研，不依赖 weixin_clawbot 包）。
///
/// 统一管理扫码绑定、消息收发、AI 自动回复。
///
/// 使用方式：
/// ```dart
/// // 应用启动时自动加载账号并连接
/// await WeixinClawbotService.instance.startup();
///
/// // 扫码绑定（弹出 QR 对话框，成功后自动连接）
/// final account = await WeixinClawbotService.instance.loginAndConnect(context);
///
/// // 监听消息
/// WeixinClawbotService.instance.messageStream.listen((msg) { ... });
/// ```
class WeixinClawbotService {
  WeixinClawbotService._();

  static final WeixinClawbotService _instance = WeixinClawbotService._();
  static WeixinClawbotService get instance => _instance;

  final WeixinAccountStore _store = WeixinAccountStore.instance;

  ClawBotAccount? _currentAccount;
  WeixinILinkClient? _client;
  StreamSubscription<WeixinMessage>? _messageSub;

  bool _autoReplyEnabled = false;
  bool _connecting = false;

  // ---------------------------------------------------------------------------
  // 状态
  // ---------------------------------------------------------------------------

  ClawBotAccount? get currentAccount => _currentAccount;
  bool get isConnected => _messageSub != null;
  bool get autoReplyEnabled => _autoReplyEnabled;

  void setAutoReply(bool enabled) {
    _autoReplyEnabled = enabled;
    LogService.info('WeixinClawbot: AI 自动回复 ${enabled ? "开启" : "关闭"}');
  }

  final StreamController<WeixinMessage> _messageController =
      StreamController<WeixinMessage>.broadcast();
  Stream<WeixinMessage> get messageStream => _messageController.stream;

  final ValueNotifier<WeixinConnectionState> connectionState =
      ValueNotifier(WeixinConnectionState.disconnected);

  // ---------------------------------------------------------------------------
  // 账号管理
  // ---------------------------------------------------------------------------

  /// 加载已保存的账号（不连接）。
  Future<ClawBotAccount?> loadAccount() async {
    try {
      _currentAccount = await _store.loadFirst();
      if (_currentAccount != null) {
        LogService.info(
          'WeixinClawbot: 已加载账号 ${_currentAccount!.botId}',
        );
      }
    } catch (e, st) {
      LogService.error('WeixinClawbot: 加载账号失败', e, st);
      _currentAccount = null;
    }
    return _currentAccount;
  }

  /// 启动服务：加载已保存账号，若存在则自动连接。
  ///
  /// 应在 [main] 中调用，无需 await（后台连接）。
  Future<void> startup({bool autoReply = false}) async {
    final account = await loadAccount();
    if (account != null) {
      await connect(autoReply: autoReply);
    }
  }

  // ---------------------------------------------------------------------------
  // 扫码登录
  // ---------------------------------------------------------------------------

  /// 弹出 QR 扫码绑定对话框，成功后自动连接。
  ///
  /// 返回绑定好的 [ClawBotAccount]，取消或失败返回 `null`。
  Future<ClawBotAccount?> loginAndConnect(
    BuildContext context, {
    bool autoReply = false,
  }) async {
    // 登录用的客户端（token 为空）
    final loginClient = WeixinILinkClient(
      token: '',
      baseUrl: _currentAccount?.baseUrl,
    );

    final account = await showWeixinQrLoginDialog(
      context: context,
      client: loginClient,
    );
    // 登录 client 已完成使命，统一释放
    loginClient.dispose();
    if (account == null) {
      return null;
    }

    // 持久化账号
    await _store.save(account);
    _currentAccount = account;
    LogService.info(
      'WeixinClawbot: 扫码成功 botId=${account.botId} '
      'baseUrl=${account.baseUrl} tokenLen=${account.token.length} '
      'defaultTo=${account.defaultTo}',
    );

    await connect(autoReply: autoReply);
    return account;
  }

  // ---------------------------------------------------------------------------
  // 连接与消息监听
  // ---------------------------------------------------------------------------

  /// 连接并开始接收消息。
  ///
  /// - 已连接时仅更新 [autoReply] 设置并返回，不会重复连接。
  /// - 正在连接时等待连接完成。
  Future<void> connect({bool autoReply = false}) async {
    if (_currentAccount == null) {
      throw WeixinClawbotException('未绑定微信账号，请先扫码登录');
    }

    _autoReplyEnabled = autoReply;

    // 已连接：仅更新自动回复设置
    if (_messageSub != null) {
      LogService.info('WeixinClawbot: 已连接，更新自动回复设置');
      return;
    }

    // 正在连接中：等待完成
    if (_connecting) {
      LogService.info('WeixinClawbot: 正在连接中，等待完成...');
      for (int i = 0; i < 60 && _connecting && _messageSub == null; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      return;
    }

    _connecting = true;
    connectionState.value = WeixinConnectionState.connecting;
    final account = _currentAccount!;
    LogService.info(
      'WeixinClawbot: 开始连接 botId=${account.botId} '
      'baseUrl=${account.baseUrl} tokenLen=${account.token.length} '
      'defaultTo=${account.defaultTo}',
    );

    try {
      // 防御：确保不存在遗留的轮询客户端（避免多个并发循环）
      _client?.stopPolling();
      _client?.dispose();
      _client = WeixinILinkClient(
        token: account.token,
        botId: account.botId,
        baseUrl: account.baseUrl,
      );

      final stream = _client!.startPolling();
      _messageSub = stream.listen(
        _onMessage,
        onError: (error, st) {
          LogService.error('WeixinClawbot: 消息流错误', error, st);
          connectionState.value = WeixinConnectionState.error;
          _scheduleReconnect();
        },
        onDone: () {
          LogService.info('WeixinClawbot: 消息流关闭');
          connectionState.value = WeixinConnectionState.disconnected;
          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      connectionState.value = WeixinConnectionState.connected;
      LogService.info('WeixinClawbot: 已连接');
    } catch (e, st) {
      connectionState.value = WeixinConnectionState.error;
      LogService.error('WeixinClawbot: 连接失败', e, st);
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  /// 自动重连（指数退避）
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  void _scheduleReconnect() {
    if (_currentAccount == null || _reconnectTimer != null) return;

    _reconnectAttempts++;
    // 指数退避：1s → 2s → 4s → 8s → 16s → 30s（上限）
    final delay = Duration(
      seconds: (_reconnectAttempts <= 5)
          ? (1 << (_reconnectAttempts - 1))
          : 30,
    );

    LogService.info(
      'WeixinClawbot: 将在 ${delay.inSeconds}s 后自动重连（第 $_reconnectAttempts 次）',
    );

    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_currentAccount == null) return;

      connectionState.value = WeixinConnectionState.reconnecting;
      try {
        await connect(autoReply: _autoReplyEnabled);
        _reconnectAttempts = 0;
      } catch (e, st) {
        LogService.error('WeixinClawbot: 自动重连失败', e, st);
        _scheduleReconnect();
      }
    });
  }

  void _onMessage(WeixinMessage msg) {
    // 持久化 context_token，供冷启动主动发送使用
    if (msg.contextToken?.isNotEmpty == true && _currentAccount != null) {
      _store.updateContextToken(
        accountId: _currentAccount!.id,
        userId: msg.fromUserId,
        contextToken: msg.contextToken!,
      );
    }

    _messageController.add(msg);

    if (!msg.isFromUser) return;

    final text = msg.textContent;
    if (text == null || text.isEmpty) return;

    LogService.info(
      'WeixinClawbot: 收到消息 from=${msg.fromUserId} '
      'text="${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
    );

    if (_autoReplyEnabled && _currentAccount != null) {
      _autoReply(msg, text);
    }
  }

  Future<void> _autoReply(WeixinMessage msg, String userText) async {
    try {
      final reply = await AgentService.chat(userText, mode: 'accept');
      if (reply.isNotEmpty && _currentAccount != null) {
        await sendText(reply, toUserId: msg.fromUserId);
        LogService.info('WeixinClawbot: AI 自动回复成功');
      }
    } catch (e, st) {
      LogService.error('WeixinClawbot: AI 自动回复失败', e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // 发送消息
  // ---------------------------------------------------------------------------

  Future<SendResult> sendText(String text, {String? toUserId}) async {
    if (_currentAccount == null) {
      throw WeixinClawbotException('未绑定微信账号');
    }
    if (_client == null) {
      throw WeixinClawbotException('未连接，请先调用 connect()');
    }

    final target = toUserId ?? _currentAccount!.defaultTo;
    if (target == null || target.isEmpty) {
      throw WeixinClawbotException('收件人 ID 为空');
    }

    LogService.info(
      'WeixinClawbot: 发送消息 to=$target '
      'text="${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
    );

    return _client!.sendText(
      toUserId: target,
      text: text,
      contextToken: _currentAccount!.contextToken,
    );
  }

  // ---------------------------------------------------------------------------
  // 断开与登出
  // ---------------------------------------------------------------------------

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _connecting = false;

    await _messageSub?.cancel();
    _messageSub = null;

    _client?.stopPolling();
    _client?.dispose();
    _client = null;

    connectionState.value = WeixinConnectionState.disconnected;
    LogService.info('WeixinClawbot: 已断开');
  }

  Future<void> logout() async {
    await disconnect();

    if (_currentAccount != null) {
      await _store.remove(_currentAccount!.id);
    }

    _currentAccount = null;
    LogService.info('WeixinClawbot: 已登出');
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _messageSub?.cancel();
    _messageController.close();
    _client?.stopPolling();
    _client?.dispose();
    connectionState.dispose();
  }
}

enum WeixinConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class WeixinClawbotException implements Exception {
  WeixinClawbotException(this.message);
  final String message;

  @override
  String toString() => 'WeixinClawbotException: $message';
}
