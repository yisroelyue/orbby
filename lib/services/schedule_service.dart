import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class ScheduleItem {
  ScheduleItem({
    required this.id,
    required this.title,
    required this.time,
    required IconData icon,
    required this.date,
    this.isDone = false,
    DateTime? createdAt,
  }) : iconCodePoint = icon.codePoint,
       createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  String time; // "HH:mm"
  int iconCodePoint; // Material图标代码点
  bool isDone;
  final DateTime createdAt;
  DateTime date; // 所属日期

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final iconCodePoint = json['iconCodePoint'] as int;
    return ScheduleItem(
      id: json['id'] as String,
      title: json['title'] as String,
      time: json['time'] as String,
      icon: IconData(
        iconCodePoint,
        fontFamily: 'MaterialIcons',
      ),
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
          : DateTime.now(),
      isDone: json['isDone'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'time': time,
        'iconCodePoint': iconCodePoint,
        'isDone': isDone,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}

class ScheduleService {
  ScheduleService._();

  static Future<File> _file() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/orbby_schedules.json');
  }

  static Future<List<ScheduleItem>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString());
      final list = json as List<dynamic>;
      return list
          .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 加载日程，未完成优先，然后按日期时间排序，最多返回 [limit] 条
  static Future<List<ScheduleItem>> loadRecent({int limit = 5}) async {
    final all = await loadAll();

    // 排序：未完成优先，然后按日期和时间排序
    all.sort((a, b) {
      // 未完成的排在前面
      if (a.isDone != b.isDone) {
        return a.isDone ? 1 : -1;
      }
      // 同状态按日期排序
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      // 同日期按时间排序
      return a.time.compareTo(b.time);
    });
    return all.take(limit).toList();
  }

  static Future<void> saveAll(List<ScheduleItem> items) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(items.map((t) => t.toJson()).toList()),
    );
  }

  static Future<ScheduleItem> add(
    String title,
    String time,
    IconData icon,
    DateTime date,
  ) async {
    final items = await loadAll();
    final item = ScheduleItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      time: time,
      icon: icon,
      date: date,
    );
    items.insert(0, item);
    await saveAll(items);
    return item;
  }

  static Future<void> update(
    String id,
    String title,
    String time,
    IconData icon,
  ) async {
    final items = await loadAll();
    final idx = items.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    items[idx].title = title;
    items[idx].time = time;
    items[idx].iconCodePoint = icon.codePoint;
    await saveAll(items);
  }

  static Future<void> toggleDone(String id) async {
    final items = await loadAll();
    final idx = items.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    items[idx].isDone = !items[idx].isDone;
    await saveAll(items);
  }

  static Future<void> remove(String id) async {
    final items = await loadAll();
    items.removeWhere((t) => t.id == id);
    await saveAll(items);
  }
}
