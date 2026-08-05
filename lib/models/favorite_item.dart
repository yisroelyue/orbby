class FavoriteFolder {
  FavoriteFolder({
    required this.id,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final DateTime createdAt;

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) {
    return FavoriteFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };
}

class FavoriteItem {
  FavoriteItem({
    required this.filePath,
    this.folderId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 文件在存储目录中的绝对路径
  String filePath;

  /// null = 未分类
  String? folderId;
  final DateTime createdAt;

  /// 文件名（不含路径）
  String get displayName {
    final segments = filePath.replaceAll('\\', '/').split('/');
    return segments.isNotEmpty ? segments.last : filePath;
  }

  /// 唯一标识，等同于 [filePath]
  String get id => filePath;

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      filePath: json['filePath'] as String,
      folderId: json['folderId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'folderId': folderId,
        'createdAt': createdAt.toIso8601String(),
      };
}
