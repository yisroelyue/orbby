import 'dart:async';

import 'package:flutter/material.dart';

import '../agent_service.dart';
import '../log_service.dart';
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
  bool _enabled = false;
  bool _connecting = false;
  bool _disconnecting = false;
  String? _lastError;

  // ---------------------------------------------------------------------------
  // 状态
  // ---------------------------------------------------------------------------

  ClawBotAccount? get currentAccount => _currentAccount;
  bool get isConnected =>
      connectionState.value == WeixinConnectionState.connected;
  bool get enabled => _enabled;
  bool get autoReplyEnabled => _autoReplyEnabled;

  WeixinServiceStatus get status => WeixinServiceStatus(
    state: connectionState.value,
    enabled: _enabled,
    hasAccount: _currentAccount != null,
    botId: _currentAccount?.botId ?? '',
    error: _lastError,
  );

  void setAutoReply(bool enabled) {
    _autoReplyEnabled = enabled;
    LogService.info('WeixinClawbot: AI 自动回复 ${enabled ? "开启" : "关闭"}', category: 'weixin');
  }

  final StreamController<WeixinMessage> _messageController =
      StreamController<WeixinMessage>.broadcast();
  Stream<WeixinMessage> get messageStream => _messageController.stream;

  final ValueNotifier<WeixinConnectionState> connectionState = ValueNotifier(
    WeixinConnectionState.disconnected,
  );
  final ValueNotifier<WeixinServiceStatus> statusNotifier = ValueNotifier(
    const WeixinServiceStatus(),
  );

  void _setConnectionState(WeixinConnectionState state, {Object? error}) {
    _lastError = error?.toString();
    connectionState.value = state;
    _notifyStatus();
  }

  void _notifyStatus() {
    statusNotifier.value = status;
  }

  // ---------------------------------------------------------------------------
  // 账号管理
  // ---------------------------------------------------------------------------

  /// 加载已保存的账号（不连接）。
  Future<ClawBotAccount?> loadAccount() async {
    try {
      _currentAccount = await _store.loadFirst();
      if (_currentAccount != null) {
        LogService.info('WeixinClawbot: 已加载账号 ${_currentAccount!.botId}', category: 'weixin');
      }
    } catch (e, st) {
      LogService.error('WeixinClawbot: 加载账号失败', exception: e, stack: st, category: 'weixin');
      _currentAccount = null;
    }
    _notifyStatus();
    return _currentAccount;
  }

  /// 启动服务：加载已保存账号，若存在则自动连接。
  ///
  /// 应在 [main] 中调用，无需 await（后台连接）。
  Future<void> startup({bool autoReply = true}) async {
    _enabled = await _store.loadEnabled();
    final account = await loadAccount();
    if (account == null && _enabled) {
      _enabled = false;
      await _store.saveEnabled(false);
      _notifyStatus();
    } else if (account != null && _enabled) {
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
    bool autoReply = true,
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

    LogService.info(
      'WeixinClawbot: 扫码成功 botId=${account.botId} '
      'baseUrl=${account.baseUrl} tokenLen=${account.token.length} '
      'defaultTo=${account.defaultTo}',
      category: 'weixin',
    );

    await bindAndConnect(account, autoReply: autoReply);
    return account;
  }

  /// 保存菜单窗口完成扫码后传入的账号，并由当前主窗口实例建立连接。
  Future<void> bindAndConnect(
    ClawBotAccount account, {
    bool autoReply = true,
  }) async {
    if (_currentAccount?.id != account.id ||
        _currentAccount?.token != account.token) {
      await disconnect();
    }
    await _store.save(account);
    _currentAccount = account;
    _autoReplyEnabled = autoReply;
    _notifyStatus();
    await setEnabled(true, autoReply: autoReply);
  }

  /// 设置用户期望的运行状态，并跨应用重启持久化。
  Future<void> setEnabled(bool enabled, {bool autoReply = true}) async {
    if (enabled) {
      if (_currentAccount == null) {
        await loadAccount();
      }
      if (_currentAccount == null) {
        throw WeixinClawbotException('未绑定微信账号，请先扫码登录');
      }

      _enabled = true;
      _autoReplyEnabled = autoReply;
      await _store.saveEnabled(true);
      await connect(autoReply: autoReply);
      return;
    }

    _enabled = false;
    await _store.saveEnabled(false);
    await disconnect();
  }

  // ---------------------------------------------------------------------------
  // 连接与消息监听
  // ---------------------------------------------------------------------------

  /// 连接并开始接收消息。
  ///
  /// - 轮询已启动时仅更新 [autoReply] 设置，不会重复连接。
  /// - 首次 `getupdates` 成功后才进入 connected 状态。
  Future<void> connect({bool autoReply = true}) async {
    if (_currentAccount == null) {
      throw WeixinClawbotException('未绑定微信账号，请先扫码登录');
    }

    _autoReplyEnabled = autoReply;

    // 轮询已启动：仅更新自动回复设置。
    if (_messageSub != null) {
      LogService.info('WeixinClawbot: 轮询已启动，更新自动回复设置', category: 'weixin');
      return;
    }

    if (_connecting) {
      return;
    }

    _connecting = true;
    _disconnecting = false;
    _setConnectionState(WeixinConnectionState.connecting);
    final account = _currentAccount!;
    LogService.info(
      'WeixinClawbot: 开始连接 botId=${account.botId} '
      'baseUrl=${account.baseUrl} tokenLen=${account.token.length} '
      'defaultTo=${account.defaultTo}',
      category: 'weixin',
    );

    try {
      // 防御：确保不存在遗留的轮询客户端（避免多个并发循环）
      _client?.stopPolling();
      _client?.dispose();
      final client = WeixinILinkClient(
        token: account.token,
        botId: account.botId,
        baseUrl: account.baseUrl,
      );
      _client = client;

      final stream = client.startPolling(
        onConnected: () {
          if (!identical(_client, client) || !_enabled) return;
          _setConnectionState(WeixinConnectionState.connected);
          LogService.info('WeixinClawbot: 已连接', category: 'weixin');
        },
        onConnectionError: (error) {
          if (!identical(_client, client) || !_enabled) return;
          _setConnectionState(WeixinConnectionState.reconnecting, error: error);
        },
      );
      _messageSub = stream.listen(
        _onMessage,
        onError: (error, st) {
          if (!identical(_client, client)) return;
          LogService.error('WeixinClawbot: 消息流错误', exception: error, stack: st, category: 'weixin');
          _setConnectionState(WeixinConnectionState.error, error: error);
        },
        onDone: () => _handleStreamDone(client),
        cancelOnError: false,
      );

      LogService.info('WeixinClawbot: 轮询已启动，等待服务端确认', category: 'weixin');
    } catch (e, st) {
      _setConnectionState(WeixinConnectionState.error, error: e);
      LogService.error('WeixinClawbot: 连接失败', exception: e, stack: st, category: 'weixin');
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  void _handleStreamDone(WeixinILinkClient client) {
    if (!identical(_client, client)) return;
    _messageSub = null;
    _client = null;
    client.dispose();

    if (_disconnecting || !_enabled) {
      _setConnectionState(WeixinConnectionState.disconnected);
      return;
    }

    LogService.warn('WeixinClawbot: 消息流意外关闭，准备重新连接', category: 'weixin');
    _setConnectionState(WeixinConnectionState.reconnecting, error: '消息流意外关闭');
    unawaited(_restartAfterUnexpectedClose());
  }

  Future<void> _restartAfterUnexpectedClose() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!_enabled || _disconnecting || _messageSub != null) return;
    try {
      await connect(autoReply: _autoReplyEnabled);
    } catch (e, st) {
      _setConnectionState(WeixinConnectionState.error, error: e);
      LogService.error('WeixinClawbot: 重新连接失败', exception: e, stack: st, category: 'weixin');
    }
  }

  void _onMessage(WeixinMessage msg) {
    // 持久化 context_token，供冷启动主动发送使用
    if (msg.contextToken?.isNotEmpty == true && _currentAccount != null) {
      final account = _currentAccount!;
      _currentAccount = account.copyWith(
        defaultTo: account.defaultTo ?? msg.fromUserId,
        contextToken: msg.contextToken,
      );
      unawaited(
        _store.updateContextToken(
          accountId: account.id,
          userId: msg.fromUserId,
          contextToken: msg.contextToken!,
        ),
      );
    }

    _messageController.add(msg);

    if (!msg.isFromUser) return;

    final text = msg.textContent;
    if (text == null || text.isEmpty) return;

    LogService.info(
      'WeixinClawbot: 收到消息 from=${msg.fromUserId} '
      'text="${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
      category: 'weixin',
    );

    if (_autoReplyEnabled && _currentAccount != null) {
      unawaited(_autoReply(msg, text));
    }
  }

  Future<void> _autoReply(WeixinMessage msg, String userText) async {
    try {
      final reply = await AgentService.chat(userText, mode: 'accept');
      if (reply.isNotEmpty && _currentAccount != null) {
        await sendText(reply, toUserId: msg.fromUserId);
        LogService.info('WeixinClawbot: AI 自动回复成功', category: 'weixin');
      }
    } catch (e, st) {
      LogService.error('WeixinClawbot: AI 自动回复失败', exception: e, stack: st, category: 'weixin');
    }
  }

  // ---------------------------------------------------------------------------
  // 发送消息
  // ---------------------------------------------------------------------------

  Future<SendResult> sendText(String text, {String? toUserId}) async {
    if (_currentAccount == null) {
      throw WeixinClawbotException('未绑定微信账号');
    }
    if (_client == null || !isConnected) {
      throw WeixinClawbotException('未连接，请先调用 connect()');
    }

    final target = toUserId ?? _currentAccount!.defaultTo;
    if (target == null || target.isEmpty) {
      throw WeixinClawbotException('收件人 ID 为空');
    }

    LogService.info(
      'WeixinClawbot: 发送消息 to=$target '
      'text="${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
      category: 'weixin',
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
    _disconnecting = true;
    _connecting = false;

    final subscription = _messageSub;
    _messageSub = null;
    final client = _client;
    _client = null;

    await subscription?.cancel();
    client?.dispose();

    _setConnectionState(WeixinConnectionState.disconnected);
    _disconnecting = false;
    LogService.info('WeixinClawbot: 已断开', category: 'weixin');
  }

  Future<void> logout() async {
    _enabled = false;
    await _store.saveEnabled(false);
    await disconnect();

    if (_currentAccount != null) {
      await _store.remove(_currentAccount!.id);
    }

    _currentAccount = null;
    _notifyStatus();
    LogService.info('WeixinClawbot: 已登出', category: 'weixin');
  }

  void dispose() {
    unawaited(_messageSub?.cancel());
    _messageController.close();
    _client?.dispose();
    connectionState.dispose();
    statusNotifier.dispose();
  }
}

class WeixinClawbotException implements Exception {
  WeixinClawbotException(this.message);
  final String message;

  @override
  String toString() => 'WeixinClawbotException: $message';
}
