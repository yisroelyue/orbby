import 'dart:convert';

/// 脚本参数定义（从脚本头部注释读取）
class ScriptParam {
  ScriptParam({
    required this.flag,
    this.type = 'str',
    this.required = false,
    this.description = '',
  });

  String flag; // 如 "-f, --file"
  String type; // str / file 等
  bool required;
  String description;

  /// 生成命令行时实际使用的 flag（优先长格式）
  String get commandFlag {
    final parts = flag
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    return parts.firstWhere((e) => e.startsWith('--'),
        orElse: () => parts.first);
  }

  /// 是否为文件选择参数
  bool get isFileType => type.toLowerCase() == 'file';

  factory ScriptParam.fromJson(Map<String, dynamic> json) {
    return ScriptParam(
      flag: json['flag'] as String? ?? json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'str',
      required: json['required'] as bool? ?? false,
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'flag': flag,
        'type': type,
        'required': required,
        'description': description,
      };
}

/// 脚本头部注释元数据
class ScriptMeta {
  ScriptMeta({
    required this.name,
    this.description = '',
    this.params = const [],
  });

  final String name;
  final String description;
  final List<ScriptParam> params;

  /// 从脚本内容中解析头部注释 JSON，失败返回 null
  static ScriptMeta? parse(String content) {
    final open = content.indexOf('{');
    if (open == -1) return null;
    final close = _findClosingBrace(content, open);
    if (close == -1) return null;
    try {
      final map = jsonDecode(content.substring(open, close + 1));
      if (map is! Map<String, dynamic>) return null;
      final name = map['name'] as String?;
      if (name == null || name.trim().isEmpty) return null;
      final rawParams = map['param'] as List<dynamic>? ?? const [];
      final params = rawParams
          .whereType<Map<String, dynamic>>()
          .map(ScriptParam.fromJson)
          .toList();
      return ScriptMeta(
        name: name,
        description: map['description'] as String? ?? '',
        params: params,
      );
    } catch (_) {
      return null;
    }
  }

  /// 从 openIndex 开始找配对的 '}'（跳过字符串内的括号）
  static int _findClosingBrace(String text, int openIndex) {
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = openIndex; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
      } else {
        if (c == '"') {
          inString = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return -1;
  }
}

/// 脚本项
class ScriptItem {
  ScriptItem({
    required this.id,
    required this.name,
    required this.scriptPath,
    this.description = '',
    List<ScriptParam>? params,
    DateTime? createdAt,
  })  : params = params ?? [],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  String scriptPath; // 脚本库中的文件路径
  String description;
  List<ScriptParam> params;
  final DateTime createdAt;

  String get _ext => scriptPath.split('.').last.toLowerCase();

  bool get _isBatch => _ext == 'bat' || _ext == 'cmd';

  /// 执行程序
  String get executable {
    switch (_ext) {
      case 'py':
        return 'python';
      case 'sh':
        return 'bash';
      case 'js':
        return 'node';
      case 'bat':
      case 'cmd':
        return 'cmd';
      default:
        return scriptPath;
    }
  }

  /// 构建执行参数列表（不含执行程序）
  List<String> buildArgs(Map<String, String> values) {
    final args = <String>[];
    if (_isBatch) args.add('/c');
    args.add(scriptPath);

    for (final param in params) {
      final flag = param.commandFlag;
      final value = values[param.flag] ?? values[flag];
      if (flag.isNotEmpty && value != null && value.isNotEmpty) {
        args.add(flag);
        args.add(value);
      }
    }
    return args;
  }

  /// 组装完整命令行（用于展示）
  String buildCommand(Map<String, String> values) {
    final parts = [executable, ...buildArgs(values)];
    return parts.map((e) => e.contains(' ') ? '"$e"' : e).join(' ');
  }

  factory ScriptItem.fromJson(Map<String, dynamic> json) {
    return ScriptItem(
      id: json['id'] as String,
      name: json['name'] as String,
      scriptPath: json['scriptPath'] as String,
      description: json['description'] as String? ?? '',
      params: (json['params'] as List<dynamic>?)
              ?.map((e) => ScriptParam.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'scriptPath': scriptPath,
        'description': description,
        'params': params.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };
}
