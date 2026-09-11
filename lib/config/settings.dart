import 'dart:convert';
import 'dart:io';

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

class PlatformApiConfig {
  PlatformApiConfig({
    this.apiKey = '',
    this.chatUrl = '',
    this.model = '',
  });

  String apiKey;
  String chatUrl;
  String model;

  factory PlatformApiConfig.fromJson(Map<String, dynamic> json) {
    return PlatformApiConfig(
      apiKey: json['apiKey'] as String? ?? '',
      chatUrl: json['chatUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'apiKey': apiKey,
    'chatUrl': chatUrl,
    'model': model,
  };
}

class AppSettings {
  AppSettings({
    this.platform = 'deepseek',
    String apiKey = '',
    String chatUrl = '',
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
    Map<String, PlatformApiConfig>? apiConfigs,
    Map<String, LogCategoryConfig>? logCategories,
  }) : apiConfigs =
           apiConfigs ??
           {
             'deepseek': PlatformApiConfig(
               apiKey: apiKey,
               chatUrl: chatUrl.isEmpty
                   ? PlatformConfig.defaultChatUrl('deepseek')
                   : chatUrl,
             ),
           },
       logCategories = logCategories ??
           {
             'system': const LogCategoryConfig(console: true, file: true),
             'llm': const LogCategoryConfig(console: true, file: false),
           };

  String platform;
  Map<String, LogCategoryConfig> logCategories;

  /// LLM 日志细粒度开关：请求 / 回复单独控制（作用于 LLMClient）
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
  Map<String, PlatformApiConfig> apiConfigs;

  /// 当前平台的便捷访问器
  PlatformApiConfig get currentApi => apiConfigs.putIfAbsent(
    platform,
    () => PlatformApiConfig(
      chatUrl: PlatformConfig.defaultChatUrl(platform),
    ),
  );

  String get apiKey => currentApi.apiKey;
  set apiKey(String v) => currentApi.apiKey = v;

  String get chatUrl => currentApi.chatUrl;
  set chatUrl(String v) => currentApi.chatUrl = v;

  String get model => currentApi.model;
  set model(String v) => currentApi.model = v;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final platform = json['platform'] as String? ?? 'deepseek';

    // 解析 apiConfigs，若不存在则从旧格式迁移
    Map<String, PlatformApiConfig> configs;
    final rawConfigs = json['apiConfigs'] as Map<String, dynamic>?;
    if (rawConfigs != null) {
      configs = rawConfigs.map(
        (k, v) =>
            MapEntry(k, PlatformApiConfig.fromJson(v as Map<String, dynamic>)),
      );
    } else {
      // 兼容旧格式：顶层 apiKey/chatUrl → 当前平台
      configs = {
        platform: PlatformApiConfig(
          apiKey: json['apiKey'] as String? ?? '',
          chatUrl: json['chatUrl'] as String? ?? '',
        ),
      };
    }

    // 确保当前平台在 configs 中存在
    configs.putIfAbsent(
      platform,
      () => PlatformApiConfig(
        chatUrl: PlatformConfig.defaultChatUrl(platform),
      ),
    );

    return AppSettings(
      platform: platform,
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
      apiConfigs: configs,
    );
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
    'platform': platform,
    'apiConfigs': apiConfigs.map((k, v) => MapEntry(k, v.toJson())),
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
