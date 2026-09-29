import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:pointycastle/export.dart';

/// 密码本条目。kind 决定分类图标：key 账号密码 / card 银行卡 /
/// server 服务器与网络 / doc 证件与资料。
class PasswordEntry {
  PasswordEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    this.kind = 'key',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  String username;
  String password;
  String kind;
  final DateTime createdAt;

  factory PasswordEntry.fromJson(Map<String, dynamic> json) => PasswordEntry(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        kind: json['kind'] as String? ?? 'key',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'kind': kind,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// 密码本数据层（**仅 note 窗口 engine 内使用**，静态状态不跨窗口）。
///
/// 主密码为 6 位数字 PIN，经 PBKDF2-SHA256（12 万轮 + 随机盐）派生
/// AES-256 密钥；条目整体序列化后 AES-CBC 加密落盘到
/// `~/.orbby/orbby_vault.json`。解锁后明文只驻留内存，lock() 即清除。
/// 明文前缀魔数用于校验 PIN 正确性（padding 正确但魔数不符同样视为失败）。
/// 锁定态副标题需要条目数，故 count 明文存于库文件头（不泄露内容）。
class PasswordVault {
  PasswordVault._();

  static const _magic = 'ORBBYPW1';
  static const _iterations = 120000;

  static List<PasswordEntry>? _entries; // null = 锁定
  static Key? _key;
  static String? _saltHex;

  static bool get isUnlocked => _entries != null;
  static List<PasswordEntry> get entries => _entries ?? const [];

  static Future<File> _file() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/orbby_vault.json');
  }

  static Future<Map<String, dynamic>?> _readRaw() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      // 库文件损坏：改名保留现场，按未设置处理，避免覆盖导致数据静默丢失。
      try {
        final file = await _file();
        if (await file.exists()) {
          await file.rename('${file.path}.corrupt');
        }
      } catch (_) {}
      return null;
    }
  }

  /// 是否已设置主密码
  static Future<bool> hasVault() async => await _readRaw() != null;

  /// 锁定态下可读的条目数
  static Future<int> entryCount() async {
    final raw = await _readRaw();
    return (raw?['count'] as num?)?.toInt() ?? 0;
  }

  /// 首次设置主密码：创建空库并保持解锁状态。
  static Future<void> setup(String pin) async {
    _saltHex = _randomHex(16);
    final derived = await compute(_deriveKeyBytes, {
      'pin': pin,
      'salt': _saltHex!,
      'iterations': _iterations,
    });
    _key = Key(Uint8List.fromList(derived));
    _entries = [];
    await _persist();
  }

  /// 用主密码解锁。成功后条目明文驻留内存；失败（PIN 错 / 库损坏）返回
  /// false 且不留任何密钥。
  static Future<bool> unlock(String pin) async {
    final raw = await _readRaw();
    if (raw == null) return false;
    try {
      final kdf = raw['kdf'] as Map<String, dynamic>;
      final saltHex = kdf['salt'] as String;
      final iterations = (kdf['iterations'] as num?)?.toInt() ?? _iterations;
      final data = base64Decode(raw['data'] as String);
      final result = await compute(_decryptVault, {
        'pin': pin,
        'salt': saltHex,
        'iterations': iterations,
        'data': data,
      });
      if (result == null) return false;
      final payload =
          jsonDecode(utf8.decode(result['plain'] as List<int>).substring(_magic.length))
              as Map<String, dynamic>;
      _saltHex = saltHex;
      _key = Key(Uint8List.fromList(result['key'] as List<int>));
      _entries = (payload['entries'] as List<dynamic>)
          .map((e) => PasswordEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return true;
    } catch (_) {
      lock();
      return false;
    }
  }

  /// 锁定：清除内存中的明文条目与派生密钥。
  static void lock() {
    _entries = null;
    _key = null;
  }

  static Future<PasswordEntry> add({
    required String title,
    required String username,
    required String password,
    String kind = 'key',
  }) async {
    final entry = PasswordEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      username: username,
      password: password,
      kind: kind,
    );
    _entries!.insert(0, entry);
    await _persist();
    return entry;
  }

  static Future<void> update(PasswordEntry entry) async {
    final idx = _entries!.indexWhere((e) => e.id == entry.id);
    if (idx == -1) return;
    _entries![idx] = entry;
    await _persist();
  }

  static Future<void> remove(String id) async {
    _entries!.removeWhere((e) => e.id == id);
    await _persist();
  }

  static Future<void> _persist() async {
    final key = _key;
    final entries = _entries;
    if (key == null || entries == null) return;
    final payload = utf8.encode('$_magic'
        '${jsonEncode({'entries': entries.map((e) => e.toJson()).toList()})}');
    final iv = IV.fromSecureRandom(16);
    final cipher = Encrypter(AES(key, mode: AESMode.cbc))
        .encryptBytes(payload, iv: iv)
        .bytes;
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'count': entries.length,
        'kdf': {'salt': _saltHex, 'iterations': _iterations},
        'data': base64Encode(iv.bytes + cipher),
      }),
    );
  }

  /// 在 isolate 中派生密钥（PBKDF2 12 万轮约上百毫秒，勿卡 UI 线程）。
  static List<int> _deriveKeyBytes(Map<String, dynamic> args) =>
      DeriveUtil().derive(
        pin: args['pin'] as String,
        saltHex: args['salt'] as String,
        iterations: args['iterations'] as int,
      );

  /// 在 isolate 中解密并校验魔数；返回派生密钥与明文字节，PIN 错误返回
  /// null（密钥一并带回，避免主 isolate 再跑一遍 PBKDF2 卡 UI）。
  static Map<String, List<int>>? _decryptVault(Map<String, dynamic> args) {
    try {
      final keyBytes = DeriveUtil().derive(
        pin: args['pin'] as String,
        saltHex: args['salt'] as String,
        iterations: args['iterations'] as int,
      );
      final key = Key(Uint8List.fromList(keyBytes));
      final data = args['data'] as List<int>;
      final iv = IV(Uint8List.fromList(data.sublist(0, 16)));
      final plain = Encrypter(AES(key, mode: AESMode.cbc))
          .decryptBytes(Encrypted(Uint8List.fromList(data.sublist(16))), iv: iv);
      if (!utf8.decode(plain).startsWith(_magic)) return null;
      return {'key': keyBytes, 'plain': plain};
    } catch (_) {
      return null; // CBC padding / UTF-8 解码失败 = PIN 错误或库损坏
    }
  }

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    const digits = '0123456789abcdef';
    return List.generate(bytes * 2, (_) => digits[rng.nextInt(16)]).join();
  }
}

/// PBKDF2 派生（isolate 入口需要 top-level / static 可调用对象）。
class DeriveUtil {
  const DeriveUtil();

  List<int> derive({
    required String pin,
    required String saltHex,
    required int iterations,
  }) {
    final salt = Uint8List.fromList([
      for (var i = 0; i + 1 < saltHex.length; i += 2)
        int.parse(saltHex.substring(i, i + 2), radix: 16),
    ]);
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(pin)));
  }
}
