import 'dart:convert';
import 'dart:io';

/// 单次余额查询记录
class CostRecord {
  final DateTime time;
  final double balance;

  CostRecord({required this.time, required this.balance});

  factory CostRecord.fromJson(Map<String, dynamic> json) {
    return CostRecord(
      time: DateTime.parse(json['time'] as String),
      balance: (json['balance'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'balance': balance,
      };
}

/// 某一天的 API 花费
class DailyCost {
  final String day; // 星期简称，如 "一"、"二"
  final double amount;

  const DailyCost({required this.day, required this.amount});
}

/// 本地 JSON 文件存储每次余额查询，用于计算每日 API 花费。
///
/// 文件路径：~/.orbby/cost_records.json
///
/// 花费计算规则：
/// - 同一天有多条记录时：花费 = 相邻记录之间所有正向差额之和
///   （余额下降 = 花费；余额上升 = 充值，不计入花费）
/// - 当天只有一条记录：花费暂设为 0，等待下一次查询
class CostRecordService {
  CostRecordService._();

  static Future<File> _file() async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/cost_records.json');
  }

  /// 读取所有日期的记录
  static Future<Map<String, List<CostRecord>>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final records = json['records'] as Map<String, dynamic>?;
      if (records == null) return {};
      return records.map((date, list) {
        final items =
            (list as List<dynamic>)
                .map((e) => CostRecord.fromJson(e as Map<String, dynamic>))
                .toList();
        return MapEntry(date, items);
      });
    } catch (_) {
      return {};
    }
  }

  /// 记录一次余额查询（追加到当天数组末尾）
  static Future<void> record(double balance) async {
    final all = await loadAll();
    final now = DateTime.now();
    final dateKey = _dateKey(now);

    final entry = CostRecord(time: now, balance: balance);
    all.putIfAbsent(dateKey, () => []).add(entry);

    // 只保留最近 90 天的数据，防止文件无限增长
    final cutoff = _dateKey(now.subtract(const Duration(days: 90)));
    all.removeWhere((date, _) => date.compareTo(cutoff) < 0);

    await _save(all);
  }

  static Future<void> _save(Map<String, List<CostRecord>> records) async {
    final file = await _file();
    final json = {
      'records': records.map(
        (date, list) => MapEntry(date, list.map((r) => r.toJson()).toList()),
      ),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  /// 获取最近 [days] 天的每日花费列表
  ///
  /// 花费 = 当天内所有相邻记录的正向差额之和（余额下降量）。
  /// 差额 ≤ 0 视为充值/赠送，不计入花费。
  /// 当天只有一条记录时花费为 0。
  static Future<List<DailyCost>> getDailyCosts({int days = 7}) async {
    final all = await loadAll();
    final now = DateTime.now();
    final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    final result = <DailyCost>[];

    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateKey = _dateKey(date);
      final records = (all[dateKey] ?? []).toList();

      double cost = 0;
      if (records.length >= 2) {
        // 按时间升序排列
        records.sort((a, b) => a.time.compareTo(b.time));
        // 累加所有正向差额（余额下降 = 花费）
        for (int j = 0; j < records.length - 1; j++) {
          final diff = records[j].balance - records[j + 1].balance;
          if (diff > 0) {
            cost += diff;
          }
          // diff <= 0 → 充值或赠送，跳过
        }
      }
      // records.length < 2 → cost 保持为 0

      // DateTime.weekday: 1=Monday .. 7=Sunday
      final dayLabel = dayLabels[date.weekday - 1];
      result.add(DailyCost(day: dayLabel, amount: cost));
    }

    return result;
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
