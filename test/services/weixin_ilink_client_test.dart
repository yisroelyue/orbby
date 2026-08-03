import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orbby/services/weixin/weixin_ilink_client.dart';
import 'package:orbby/services/weixin/weixin_models.dart';

void main() {
  test('service status survives cross-window serialization', () {
    const status = WeixinServiceStatus(
      state: WeixinConnectionState.reconnecting,
      enabled: true,
      hasAccount: true,
      botId: 'bot-id',
      error: 'temporary failure',
    );

    final decoded = WeixinServiceStatus.fromJson(status.toJson());

    expect(decoded.state, WeixinConnectionState.reconnecting);
    expect(decoded.enabled, isTrue);
    expect(decoded.hasAccount, isTrue);
    expect(decoded.botId, 'bot-id');
    expect(decoded.error, 'temporary failure');
  });

  test('polling reports connected only after a successful response', () async {
    final connected = Completer<void>();
    late final WeixinILinkClient client;
    client = WeixinILinkClient(
      token: 'token',
      botId: 'bot-id',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ret': 0,
            'errcode': 0,
            'msgs': <Object>[],
            'get_updates_buf': 'cursor',
            'longpolling_timeout_ms': 35000,
          }),
          200,
        );
      }),
    );

    client.startPolling(
      onConnected: () {
        if (!connected.isCompleted) connected.complete();
        client.stopPolling();
      },
    );

    await connected.future.timeout(const Duration(seconds: 1));
    client.dispose();
  });

  test('polling exposes API errors instead of reporting connected', () async {
    final failed = Completer<Object>();
    var connected = false;
    late final WeixinILinkClient client;
    client = WeixinILinkClient(
      token: 'invalid-token',
      botId: 'bot-id',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ret': -1,
            'errcode': -14,
            'errmsg': 'session timeout',
            'msgs': <Object>[],
          }),
          200,
        );
      }),
    );

    client.startPolling(
      onConnected: () => connected = true,
      onConnectionError: (error) {
        if (!failed.isCompleted) failed.complete(error);
        client.stopPolling();
      },
    );

    final error = await failed.future.timeout(const Duration(seconds: 1));
    expect('$error', contains('errcode=-14'));
    expect(connected, isFalse);
    client.dispose();
  });
}
