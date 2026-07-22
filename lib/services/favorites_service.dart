import 'dart:convert';
import 'dart:io';

import '../models/favorite_item.dart';

class _FavoritesData {
  _FavoritesData({List<FavoriteFolder>? folders, List<FavoriteItem>? items})
      : folders = folders ?? [],
        items = items ?? [];

  List<FavoriteFolder> folders;
  List<FavoriteItem> items;

  factory _FavoritesData.fromJson(Map<String, dynamic> json) {
    return _FavoritesData(
      folders: (json['folders'] as List<dynamic>?)
              ?.map((e) => FavoriteFolder.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => FavoriteItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'folders': folders.map((f) => f.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
      };
}

class FavoritesService {
  FavoritesService._();

  static Future<File> _file() async {
    final dir = await _orbbyDir();
    return File('${dir.path}/orbby_favorites.json');
  }

  static Future<Directory> _orbbyDir() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Directory('$home/.orbby');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _favoritesStorageDir() async {
    final paw = await _orbbyDir();
    final dir = Directory('${paw.path}/favorites');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取真实文件夹路径
  static Future<Directory> _getRealFolderDir(String folderName) async {
    final storageDir = await _favoritesStorageDir();
    final dir = Directory('${storageDir.path}/$folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<_FavoritesData> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return _FavoritesData();
      final json = jsonDecode(await file.readAsString());
      return _FavoritesData.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return _FavoritesData();
    }
  }

  static Future<void> _save(_FavoritesData data) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
    );
  }

  // ── Folders ──────────────────────────────────────────────

  static Future<List<FavoriteFolder>> loadFolders() async {
    final data = await _load();
    return data.folders;
  }

  static Future<FavoriteFolder> addFolder(String name) async {
    final data = await _load();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final folder = FavoriteFolder(
      id: id,
      name: name,
    );
    data.folders.add(folder);
    await _save(data);
    // 创建真实文件夹
    await _getRealFolderDir(name);
    return folder;
  }

  static Future<void> renameFolder(String id, String name) async {
    final data = await _load();
    final idx = data.folders.indexWhere((f) => f.id == id);
    if (idx == -1) return;
    final oldName = data.folders[idx].name;
    data.folders[idx].name = name;
    await _save(data);
    // 重命名真实文件夹
    final storageDir = await _favoritesStorageDir();
    final oldDir = Directory('${storageDir.path}/$oldName');
    final newDir = Directory('${storageDir.path}/$name');
    if (await oldDir.exists()) {
      await oldDir.rename(newDir.path);
    }
  }

  static Future<void> removeFolder(String id) async {
    final data = await _load();
    final idx = data.folders.indexWhere((f) => f.id == id);
    if (idx == -1) return;
    final folderName = data.folders[idx].name;
    data.folders.removeAt(idx);
    // Move items in this folder to uncategorized.
    for (final item in data.items) {
      if (item.folderId == id) {
        item.folderId = null;
      }
    }
    await _save(data);
    // 删除真实文件夹
    final storageDir = await _favoritesStorageDir();
    final dir = Directory('${storageDir.path}/$folderName');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // ── Items ────────────────────────────────────────────────

  static Future<List<FavoriteItem>> loadItems({String? folderId}) async {
    final data = await _load();
    if (folderId == null) {
      return data.items.where((i) => i.folderId == null).toList();
    }
    return data.items.where((i) => i.folderId == folderId).toList();
  }

  static Future<List<FavoriteItem>> loadAllItems() async {
    final data = await _load();
    return data.items;
  }

  static Future<FavoriteItem> add(String filePath, {String? folderId}) async {
    final data = await _load();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final src = File(filePath);
    final baseName = filePath.replaceAll('\\', '/').split('/').last;

    String destPath;
    if (folderId != null) {
      // 复制到真实文件夹
      final folder = data.folders.firstWhere((f) => f.id == folderId);
      final folderDir = await _getRealFolderDir(folder.name);
      destPath = '${folderDir.path}/$baseName';
      await src.copy(destPath);
    } else {
      // 未分类的放到 favorites 根目录
      final storageDir = await _favoritesStorageDir();
      destPath = '${storageDir.path}/$baseName';
      await src.copy(destPath);
    }

    final item = FavoriteItem(
      id: id,
      filePath: destPath,
      folderId: folderId,
    );
    // Deduplicate by original filePath (now stored as displayName source)
    data.items.removeWhere((i) => i.filePath == destPath);
    data.items.insert(0, item);
    await _save(data);
    return item;
  }

  static Future<void> remove(String id) async {
    final data = await _load();
    final idx = data.items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      // Delete the copied file from storage
      final itemPath = data.items[idx].filePath;
      try {
        final file = File(itemPath);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        // File already gone.
      }
    }
    data.items.removeWhere((i) => i.id == id);
    await _save(data);
  }

  static Future<void> moveToFolder(String itemId, String? folderId) async {
    final data = await _load();
    final idx = data.items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;

    final item = data.items[idx];
    final oldFilePath = item.filePath;
    final baseName = oldFilePath.replaceAll('\\', '/').split('/').last;

    String newFilePath;
    if (folderId != null) {
      // 移动到目标文件夹
      final folder = data.folders.firstWhere((f) => f.id == folderId);
      final folderDir = await _getRealFolderDir(folder.name);
      newFilePath = '${folderDir.path}/$baseName';
    } else {
      // 移动到未分类目录
      final storageDir = await _favoritesStorageDir();
      newFilePath = '${storageDir.path}/$baseName';
    }

    // 移动文件
    final oldFile = File(oldFilePath);
    if (await oldFile.exists()) {
      await oldFile.rename(newFilePath);
    }

    item.filePath = newFilePath;
    item.folderId = folderId;
    await _save(data);
  }

  static Future<int> uncategorizedCount() async {
    final data = await _load();
    return data.items.where((i) => i.folderId == null).length;
  }
}
