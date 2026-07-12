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
    required this.id,
    required this.filePath,
    String? displayName,
    this.folderId,
    DateTime? createdAt,
  })  : displayName = displayName ?? _extractName(filePath),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String filePath;
  final String displayName;
  String? folderId; // null = uncategorized
  final DateTime createdAt;

  static String _extractName(String path) {
    final segments = path.replaceAll('\\', '/').split('/');
    return segments.isNotEmpty ? segments.last : path;
  }

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      displayName: json['displayName'] as String?,
      folderId: json['folderId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'displayName': displayName,
        'folderId': folderId,
        'createdAt': createdAt.toIso8601String(),
      };
}
