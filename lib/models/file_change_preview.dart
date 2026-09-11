class FileChangePreview {
  FileChangePreview({required this.path, required this.operation, required this.diff, required this.additions, required this.deletions, this.truncated = false});
  final String path; final String operation; final String diff; final int additions; final int deletions; final bool truncated;
  factory FileChangePreview.fromJson(Map<String, dynamic> json) => FileChangePreview(path: '${json['path'] ?? ''}', operation: '${json['operation'] ?? 'edit'}', diff: '${json['diff'] ?? ''}', additions: (json['additions'] as num?)?.toInt() ?? 0, deletions: (json['deletions'] as num?)?.toInt() ?? 0, truncated: json['truncated'] == true);
  Map<String, dynamic> toJson() => {'path': path, 'operation': operation, 'diff': diff, 'additions': additions, 'deletions': deletions, 'truncated': truncated};
}
