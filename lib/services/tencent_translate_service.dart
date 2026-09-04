import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/settings.dart';
import 'translate_service.dart';

/// 腾讯云机器翻译客户端。SecretKey 只用于本地签名，不会放入请求体。
class TencentTranslateService implements TranslationProvider {
  TencentTranslateService({http.Client? client}) : _client = client ?? http.Client();

  static const endpoint = 'tmt.tencentcloudapi.com';
  static const service = 'tmt';
  static const version = '2018-03-21';

  final http.Client _client;
  @override
  Future<String> translate(String text, {required TranslateLang lang}) async {
    final settings = await SettingsService.load();
    final id = settings.tencentSecretId.trim();
    final key = settings.tencentSecretKey.trim();
    if (id.isEmpty || key.isEmpty) {
      throw TranslateException('请先配置腾讯云 SecretId 和 SecretKey');
    }

    final target = _targetLanguage(lang, text);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final body = jsonEncode({
      'SourceText': text,
      'Source': 'auto',
      'Target': target,
      'ProjectId': settings.tencentProjectId,
    });
    final authorization = _authorization(
      secretId: id,
      secretKey: key,
      timestamp: timestamp,
      body: body,
    );

    final response = await _client.post(
      Uri.https(endpoint, '/'),
      headers: {
        'Authorization': authorization,
        'Content-Type': 'application/json; charset=utf-8',
        'Host': endpoint,
        'X-TC-Action': 'TextTranslate',
        'X-TC-Version': version,
        'X-TC-Region': settings.tencentRegion,
        'X-TC-Timestamp': '$timestamp',
      },
      body: body,
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final error = (json['Response'] as Map?)?['Error'] as Map?;
    if (response.statusCode < 200 || response.statusCode >= 300 || error != null) {
      throw TranslateException('腾讯翻译请求失败：${error?['Message'] ?? response.statusCode}');
    }
    final result = (json['Response'] as Map?)?['TargetText'];
    if (result is! String) throw TranslateException('腾讯翻译返回结果无效');
    return result;
  }

  String _authorization({required String secretId, required String secretKey,
      required int timestamp, required String body}) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true)
        .toIso8601String().substring(0, 10);
    final signedHeaders = 'content-type;host';
    final canonicalHeaders = 'content-type:application/json; charset=utf-8\nhost:$endpoint\n';
    final hashedBody = sha256.convert(utf8.encode(body)).toString();
    final canonicalRequest = 'POST\n/\n\n$canonicalHeaders\n$signedHeaders\n$hashedBody';
    final credentialScope = '$date/$service/tc3_request';
    final stringToSign = 'TC3-HMAC-SHA256\n$timestamp\n$credentialScope\n'
        '${sha256.convert(utf8.encode(canonicalRequest))}';
    final secretDate = _hmac(utf8.encode('TC3$secretKey'), date);
    final secretService = _hmac(secretDate, service);
    final secretSigning = _hmac(secretService, 'tc3_request');
    final signature = Hmac(sha256, secretSigning)
        .convert(utf8.encode(stringToSign)).toString();
    return 'TC3-HMAC-SHA256 Credential=$secretId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
  }

  List<int> _hmac(List<int> key, String value) => Hmac(sha256, key)
      .convert(utf8.encode(value)).bytes;

  String _targetLanguage(TranslateLang lang, String text) {
    final chinese = TranslateTask.isChinese(text);
    if (!chinese && lang == TranslateLang.zhEn) return 'zh';
    return switch (lang) {
      TranslateLang.zhEn => 'en', TranslateLang.zhJa => 'ja',
      TranslateLang.zhKo => 'ko', TranslateLang.zhFr => 'fr',
      TranslateLang.zhDe => 'de', TranslateLang.zhEs => 'es',
    };
  }

  void dispose() => _client.close();
}
