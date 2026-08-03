import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import '../config/settings.dart';

class BalanceInfo {
  BalanceInfo({
    required this.isAvailable,
    required this.totalBalance,
    required this.grantedBalance,
    required this.toppedUpBalance,
    required this.currency,
  });

  final bool isAvailable;
  final double totalBalance;
  final double grantedBalance;
  final double toppedUpBalance;
  final String currency;

  factory BalanceInfo.fromJson(Map<String, dynamic> json) {
    final infos = json['balance_infos'] as List<dynamic>?;
    if (infos == null || infos.isEmpty) {
      return BalanceInfo(
        isAvailable: json['is_available'] as bool? ?? false,
        totalBalance: 0,
        grantedBalance: 0,
        toppedUpBalance: 0,
        currency: 'CNY',
      );
    }
    final info = infos.first as Map<String, dynamic>;
    return BalanceInfo(
      isAvailable: json['is_available'] as bool? ?? false,
      totalBalance: double.tryParse(info['total_balance'] as String? ?? '0') ?? 0,
      grantedBalance: double.tryParse(info['granted_balance'] as String? ?? '0') ?? 0,
      toppedUpBalance: double.tryParse(info['topped_up_balance'] as String? ?? '0') ?? 0,
      currency: info['currency'] as String? ?? 'CNY',
    );
  }
}

class BalanceService {
  BalanceService._();

  /// 通过发送一条最小对话请求测试 API 连通性
  static Future<bool> testConnectivity() async {
    final settings = await SettingsService.load();
    if (settings.apiKey.isEmpty) return false;

    final chatUrl = settings.chatUrl.isEmpty
        ? PlatformConfig.defaultChatUrl(settings.platform)
        : settings.chatUrl.trim();
    final model = settings.model.isEmpty
        ? PlatformConfig.defaultChatModel(settings.platform)
        : settings.model;

    final uri = Uri.parse(chatUrl);
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
      'max_tokens': 1,
    });

    
    
    

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer ${settings.apiKey}');
      final bytes = utf8.encode(body);
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      final raw = await response.transform(utf8.decoder).join();
      
      return response.statusCode == 200;
    } catch (e) {
      
      return false;
    } finally {
      client.close();
    }
  }

  static Future<BalanceInfo> fetchBalance() async {
    final settings = await SettingsService.load();

    final uri = Uri.parse(settings.balanceUrl.trim());
    // 
    // 
    // 

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer ${settings.apiKey}');
      request.headers.set('Accept', 'application/json');

      final response = await request.close().timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw BalanceException('请求超时'),
          );
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw BalanceException('HTTP ${response.statusCode}');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      return BalanceInfo.fromJson(json);
    } finally {
      client.close();
    }
  }

}

class BalanceException implements Exception {
  BalanceException(this.message);
  final String message;

  @override
  String toString() => message;
}
