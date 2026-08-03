/// 机器人账号凭证的持久化存储（自研，使用 SharedPreferences）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'weixin_models.dart';

const _kAccountsKey = 'weixin_clawbot_accounts';
const _kEnabledKey = 'weixin_clawbot_enabled';

/// 跨应用重启持久化 [ClawBotAccount] 凭证。
class WeixinAccountStore {
  WeixinAccountStore._();

  static WeixinAccountStore? _instance;

  /// 返回单例。
  static WeixinAccountStore get instance =>
      _instance ??= WeixinAccountStore._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// 保存 [account]，覆盖同 [ClawBotAccount.id] 的旧条目。
  Future<void> save(ClawBotAccount account) async {
    final all = await loadAll();
    final updated = {for (final a in all) a.id: a, account.id: account};
    await _persist(updated.values.toList());
  }

  /// 仅为 [accountId] 更新 [contextToken]，可选更新 [defaultTo]。
  /// 账号不存在则无操作。
  Future<void> updateContextToken({
    required String accountId,
    required String userId,
    required String contextToken,
  }) async {
    final all = await loadAll();
    final updated = all.map((a) {
      if (a.id != accountId) return a;
      // 只存 defaultTo/contextToken 对中的最新 token。
      return a.copyWith(
        defaultTo: a.defaultTo ?? userId,
        contextToken: contextToken,
      );
    }).toList();
    await _persist(updated);
  }

  /// 返回所有已存账号。
  Future<List<ClawBotAccount>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kAccountsKey) ?? [];
    return raw
        .map((s) {
          try {
            return ClawBotAccount.fromJson(
              jsonDecode(s) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<ClawBotAccount>()
        .toList();
  }

  /// 返回第一个已存账号，不存在则返回 `null`。
  Future<ClawBotAccount?> loadFirst() async {
    final all = await loadAll();
    return all.isEmpty ? null : all.first;
  }

  /// 服务是否应在应用启动时自动连接。旧版本默认保持开启。
  Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? true;
  }

  Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, enabled);
  }

  /// 移除指定 [accountId] 的账号。
  Future<void> remove(String accountId) async {
    final all = await loadAll();
    await _persist(all.where((a) => a.id != accountId).toList());
  }

  /// 移除所有已存账号。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccountsKey);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _persist(List<ClawBotAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kAccountsKey,
      accounts.map((a) => jsonEncode(a.toJson())).toList(),
    );
  }
}
