import 'dart:convert';
import 'dart:io';

import 'api_profile.dart';
import 'platform.dart';

/// 单类日志的开关配置
class LogCategoryConfig {
  final bool console;
  final bool file;

  const LogCategoryConfig({
    this.console = true,
    this.file = true,
  });

  factory LogCategoryConfig.fromJson(Map<String, dynamic> json) {
    return LogCategoryConfig(
      console: json['console'] as bool? ?? true,
      file: json['file'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'console': console,
    'file': file,
  };

  LogCategoryConfig copyWith({bool? console, bool? file}) {
    return LogCategoryConfig(
      console: console ?? this.console,
      file: file ?? this.file,
    );
  }
}

class AppSettings {
  AppSettings({
    List<ApiProfile>? profiles,
    this.activeProfileId = '',
    this.llmLogRequest = true,
    this.llmLogResponse = false,
    this.translationProvider = 'llm',
    this.tencentSecretId = '',
    this.tencentSecretKey = '',
    this.tencentRegion = 'ap-guangzhou',
    this.tencentProjectId = 0,
    this.agentSystemPrompt = '',
    this.agentUsageRules = '',
    this.panelAppIds = const [],
    this.showSessionTabs = true,
    Map<String, LogCategoryConfig>? logCategories,
  }) : profiles = profiles ?? [_defaultProfile()],
       logCategories = logCategories ??
           {
             'system': const LogCategoryConfig(console: true, file: true),
             'llm': const LogCategoryConfig(console: true, file: false),
           } {
    _normalize();
  }

  /// API 配置列表（用户可自由增删，内置平台模板只是新增时的填充预设）
  List<ApiProfile> profiles;

  /// 当前激活的配置 id（聊天与翻译/分析都用这一份）
  String activeProfileId;

  bool llmLogRequest;
  bool llmLogResponse;
  String translationProvider;
  String tencentSecretId;
  String tencentSecretKey;
  String tencentRegion;
  int tencentProjectId;
  String agentSystemPrompt;
  String agentUsageRules;
  List<String> panelAppIds; // 服务面板展示的应用 id 列表
  bool showSessionTabs; // HomeScreen 顶部是否显示会话标签
  Map<String, LogCategoryConfig> logCategories;

  /// 当前激活的配置（纯读，无写副作用）：id 悬空时回退首条。
  /// 恒有值——构造与 fromJson 都经 [_normalize] 保证 profiles 非空
  ApiProfile get activeProfile {
    for (final p in profiles) {
      if (p.id == activeProfileId) return p;
    }
    return profiles.first;
  }

  /// 规范化不变式：profiles 至少一条（空则补 DeepSeek 默认模板）、
  /// activeProfileId 必须指向列表内某条（悬空则取首条）。
  /// load 时统一兜底，save 写出的永远是规范化结果
  void _normalize() {
    if (profiles.isEmpty) {
      profiles = [_defaultProfile()];
    }
    if (!profiles.any((p) => p.id == activeProfileId)) {
      activeProfileId = profiles.first.id;
    }
  }

  /// 全新安装的默认配置（DeepSeek 官方模板，Key 留空待填）
  static ApiProfile _defaultProfile() => ApiProfile(
    name: 'DeepSeek',
    protocol: ApiProtocol.openai,
    baseUrl: PlatformConfig.defaultChatUrl('deepseek'),
    model: PlatformConfig.defaultChatModel('deepseek'),
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // LLM 日志细粒度开关：请求 / 回复单独控制（作用于 LLMClient）
    final (profiles, activeId) = _parseProfiles(json);
    return AppSettings(
      profiles: profiles,
      activeProfileId: activeId,
      logCategories: _withLlmConsoleAlwaysOn(_parseLogCategories(json)),
      llmLogRequest: json['llmLogRequest'] as bool? ?? true,
      llmLogResponse: json['llmLogResponse'] as bool? ?? false,
      translationProvider: json['translationProvider'] as String? ?? 'llm',
      tencentSecretId: json['tencentSecretId'] as String? ?? '',
      tencentSecretKey: json['tencentSecretKey'] as String? ?? '',
      tencentRegion: json['tencentRegion'] as String? ?? 'ap-guangzhou',
      tencentProjectId: json['tencentProjectId'] as int? ?? 0,
      agentSystemPrompt: json['agentSystemPrompt'] as String? ?? '',
      agentUsageRules: json['agentUsageRules'] as String? ?? '',
      panelAppIds:
          (json['panelAppIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      showSessionTabs: json['showSessionTabs'] as bool? ?? true,
    );
  }

  /// 解析 API 配置：新格式（profiles + activeProfileId）直接读；
  /// 旧格式（platform + apiConfigs）一次性迁移为配置列表——每个平台条目
  /// 生成一份配置（baseUrl/model 空则回退平台默认值**填死**，此后消费方
  /// 不再做默认回退），激活项对准旧 platform
  static (List<ApiProfile>, String) _parseProfiles(
    Map<String, dynamic> json,
  ) {
    final rawProfiles = json['profiles'] as List<dynamic>?;
    if (rawProfiles != null) {
      final id = json['activeProfileId'] as String? ?? '';
      return (
        rawProfiles
            .map((e) => ApiProfile.fromJson(e as Map<String, dynamic>))
            .toList(),
        id,
      );
    }

    // ── 旧格式迁移 ──
    final platform = json['platform'] as String? ?? 'deepseek';
    Map<String, dynamic>? rawConfigs = json['apiConfigs'] as Map<String, dynamic>?;
    if (rawConfigs == null) {
      // 更旧的格式：顶层 apiKey/chatUrl → 当前平台一条
      final apiKey = json['apiKey'] as String? ?? '';
      final chatUrl = json['chatUrl'] as String? ?? '';
      if (apiKey.isNotEmpty || chatUrl.isNotEmpty) {
        rawConfigs = {
          platform: {'apiKey': apiKey, 'chatUrl': chatUrl},
        };
      }
    }
    final configs = <String, Map<String, dynamic>>{};
    rawConfigs?.forEach((k, v) {
      if (v is Map<String, dynamic>) configs[k] = v;
    });
    configs.putIfAbsent(platform, () => const {});

    final profiles = <ApiProfile>[];
    for (final entry in configs.entries) {
      final key = entry.key;
      final apiKey = entry.value['apiKey'] as String? ?? '';
      final chatUrl = entry.value['chatUrl'] as String? ?? '';
      final model = entry.value['model'] as String? ?? '';
      profiles.add(
        ApiProfile(
          // 确定性 id：多 engine 并发迁移生成相同结果，写盘等价
          id: 'migrated-$key',
          name: PlatformConfig.platforms[key]?.name ?? key,
          protocol: key == 'anthropic'
              ? ApiProtocol.anthropic
              : ApiProtocol.openai,
          baseUrl: chatUrl.trim().isEmpty
              ? PlatformConfig.defaultChatUrl(key)
              : chatUrl.trim(),
          apiKey: apiKey,
          model: model.trim().isEmpty
              ? PlatformConfig.defaultChatModel(key)
              : model.trim(),
        ),
      );
    }
    return (profiles, 'migrated-$platform');
  }

  /// 从 JSON 解析 logCategories（旧版的 llmLogEnabled 开关已由
  /// llmLogRequest/llmLogResponse 接管，不再读取）
  static Map<String, LogCategoryConfig> _parseLogCategories(
    Map<String, dynamic> json,
  ) {
    final raw = json['logCategories'] as Map<String, dynamic>?;
    if (raw != null) {
      return raw.map(
        (k, v) => MapEntry(
          k,
          LogCategoryConfig.fromJson(v as Map<String, dynamic>),
        ),
      );
    }
    // 从旧格式迁移：llm 的输出控制已由 llmLogRequest/llmLogResponse 接管
    return {
      'system': const LogCategoryConfig(console: true, file: true),
      'llm': const LogCategoryConfig(console: true, file: false),
    };
  }

  /// llm 分类的输出由"请求日志/回复日志"细粒度开关控制（LLMClient 层），
  /// LogService 层面对 llm 分类恒开，避免这里关掉导致细粒度开关失效。
  static Map<String, LogCategoryConfig> _withLlmConsoleAlwaysOn(
    Map<String, LogCategoryConfig> categories,
  ) {
    final cur = categories['llm'] ?? const LogCategoryConfig();
    categories['llm'] = cur.copyWith(console: true);
    return categories;
  }

  Map<String, dynamic> toJson() => {
    'profiles': profiles.map((p) => p.toJson()).toList(),
    'activeProfileId': activeProfileId,
    'logCategories': logCategories.map((k, v) => MapEntry(k, v.toJson())),
    'llmLogRequest': llmLogRequest,
    'llmLogResponse': llmLogResponse,
    'translationProvider': translationProvider,
    'tencentSecretId': tencentSecretId,
    'tencentSecretKey': tencentSecretKey,
    'tencentRegion': tencentRegion,
    'tencentProjectId': tencentProjectId,
    'agentSystemPrompt': agentSystemPrompt,
    'agentUsageRules': agentUsageRules,
    'panelAppIds': panelAppIds,
    'showSessionTabs': showSessionTabs,
  };
}

class SettingsService {
  SettingsService._();

  static Future<File> _file() async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby/setting');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/orbby_settings.json');
  }

  static Future<AppSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return AppSettings();
      final json = jsonDecode(await file.readAsString());
      return AppSettings.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  static Future<void> save(AppSettings settings) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
