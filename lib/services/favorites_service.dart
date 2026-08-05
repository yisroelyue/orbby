import 'dart:convert';
import 'dart:io';

import '../models/favorite_item.dart';

/// 仅保存文件夹列表，文件直接通过目录扫描发现。
class _FavoritesData {
  _FavoritesData({List<FavoriteFolder>? folders})
      : folders = folders ?? [];

  List<FavoriteFolder> folders;

  factory _FavoritesData.fromJson(Map<String, dynamic> json) {
    return _FavoritesData(
      folders: (json['folders'] as List<dynamic>?)
              ?.map((e) => FavoriteFolder.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'folders': folders.map((f) => f.toJson()).toList(),
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

  /// 扫描目录，返回 [FavoriteItem] 列表（按修改时间倒序）
  static Future<List<FavoriteItem>> _scanDir(
    String dirPath,
    String? folderId,
  ) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final items = <FavoriteItem>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = entity.path.replaceAll('\\', '/').split('/').last;
        if (name.startsWith('.')) continue; // 跳过隐藏文件
        items.add(FavoriteItem(
          filePath: entity.path,
          folderId: folderId,
          createdAt: await entity.lastModified(),
        ));
      }
    }
    // 最近修改的排前面
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// 确保目标文件不存在，存在则删除（用于覆盖）
  static Future<void> _ensureNotExists(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  // ── Folders ──────────────────────────────────────────────

  static Future<List<FavoriteFolder>> loadFolders() async {
    final data = await _load();
    return data.folders;
  }

  static Future<FavoriteFolder> addFolder(String name) async {
    final data = await _load();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final folder = FavoriteFolder(id: id, name: name);
    data.folders.add(folder);
    await _save(data);
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
    await _save(data);

    // 把文件夹内的文件移至未分类目录
    final storageDir = await _favoritesStorageDir();
    final folderDir = Directory('${storageDir.path}/$folderName');
    if (await folderDir.exists()) {
      await for (final entity in folderDir.list()) {
        if (entity is File) {
          final name = entity.path.replaceAll('\\', '/').split('/').last;
          final destPath = '${storageDir.path}/$name';
          await _ensureNotExists(destPath);
          await entity.rename(destPath);
        }
      }
      await folderDir.delete(recursive: true);
    }
  }

  // ── Items ────────────────────────────────────────────────

  /// 加载指定文件夹的文件列表
  static Future<List<FavoriteItem>> loadItems({String? folderId}) async {
    final storageDir = await _favoritesStorageDir();
    if (folderId == null) {
      return _scanDir(storageDir.path, null);
    }
    final folders = await loadFolders();
    final idx = folders.indexWhere((f) => f.id == folderId);
    if (idx == -1) return [];
    final folderName = folders[idx].name;
    return _scanDir('${storageDir.path}/$folderName', folderId);
  }

  /// 加载全部文件（未分类 + 各文件夹）
  static Future<List<FavoriteItem>> loadAllItems() async {
    final storageDir = await _favoritesStorageDir();
    final folders = await loadFolders();
    final items = <FavoriteItem>[];

    // 未分类（favorites 根目录下的文件）
    items.addAll(await _scanDir(storageDir.path, null));

    // 各文件夹
    for (final folder in folders) {
      final folderDir = Directory('${storageDir.path}/${folder.name}');
      items.addAll(await _scanDir(folderDir.path, folder.id));
    }

    return items;
  }

  /// 添加文件：直接复制到目标目录
  static Future<FavoriteItem> add(String filePath, {String? folderId}) async {
    final src = File(filePath);
    if (!await src.exists()) {
      throw FileSystemException('源文件不存在', filePath);
    }
    final baseName = filePath.replaceAll('\\', '/').split('/').last;

    String destPath;
    if (folderId != null) {
      final folders = await loadFolders();
      final folder = folders.firstWhere(
        (f) => f.id == folderId,
        orElse: () => throw StateError('文件夹不存在: $folderId'),
      );
      final folderDir = await _getRealFolderDir(folder.name);
      destPath = '${folderDir.path}/$baseName';
    } else {
      final storageDir = await _favoritesStorageDir();
      destPath = '${storageDir.path}/$baseName';
    }

    await _ensureNotExists(destPath);
    await src.copy(destPath);

    final destFile = File(destPath);
    return FavoriteItem(
      filePath: destPath,
      folderId: folderId,
      createdAt: await destFile.lastModified(),
    );
  }

  /// 删除文件
  static Future<void> remove(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // 文件已经不存在，忽略
    }
  }

  /// 移动文件到目标文件夹
  static Future<void> moveToFolder(String filePath, String? folderId) async {
    final oldFile = File(filePath);
    if (!await oldFile.exists()) return;

    final baseName = filePath.replaceAll('\\', '/').split('/').last;

    String newPath;
    if (folderId != null) {
      final folders = await loadFolders();
      final folder = folders.firstWhere(
        (f) => f.id == folderId,
        orElse: () => throw StateError('文件夹不存在: $folderId'),
      );
      final folderDir = await _getRealFolderDir(folder.name);
      newPath = '${folderDir.path}/$baseName';
    } else {
      final storageDir = await _favoritesStorageDir();
      newPath = '${storageDir.path}/$baseName';
    }

    if (newPath == filePath) return; // 同一个位置
    await _ensureNotExists(newPath);
    await oldFile.rename(newPath);
  }

  /// 未分类文件数
  static Future<int> uncategorizedCount() async {
    final storageDir = await _favoritesStorageDir();
    if (!await storageDir.exists()) return 0;
    int count = 0;
    await for (final entity in storageDir.list()) {
      if (entity is File) {
        final name = entity.path.replaceAll('\\', '/').split('/').last;
        if (!name.startsWith('.')) count++;
      }
    }
    return count;
  }
}
