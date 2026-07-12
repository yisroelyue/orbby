import 'dart:convert';
import 'dart:io';

class PhotoWallService {
  PhotoWallService._();

  static Future<File> _file() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/photo_wall.json');
  }

  /// 加载照片路径列表
  static Future<List<String>> loadPhotos() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final list = json['photos'] as List<dynamic>? ?? [];
      return list.map((e) => e as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存照片路径列表
  static Future<void> savePhotos(List<String> photos) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'photos': photos}),
    );
  }

  /// 添加照片
  static Future<void> addPhoto(String path) async {
    final photos = await loadPhotos();
    if (!photos.contains(path)) {
      photos.add(path);
      await savePhotos(photos);
    }
  }

  /// 移除照片
  static Future<void> removePhoto(String path) async {
    final photos = await loadPhotos();
    photos.remove(path);
    await savePhotos(photos);
  }
}
