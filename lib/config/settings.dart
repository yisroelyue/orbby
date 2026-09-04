import 'dart:convert';
import 'dart:io';

import '../services/translate_service.dart';
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
    this.appTheme = 'light',
    this.showTranslateLangSelector = true,
    this.translationProvider = 'llm',
    this.tencentSecretId = '',
    this.tencentSecretKey = '',
    this.tencentRegion = 'ap-guangzhou',
    this.tencentProjectId = 0,
    this.panelAppIds = const [],
    List<String>? translateEnabledLangs,
    Map<String, PlatformApiConfig>? apiConfigs,
    Map<String, LogCategoryConfig>? logCategories,
  }) : translateEnabledLangs =
           translateEnabledLangs ??
           TranslateLang.values.map((e) => e.name).toList(),
       apiConfigs =
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
  String appTheme;
  bool showTranslateLangSelector; // 是否显示翻译面板的语言选择器
  String translationProvider;
  String tencentSecretId;
  String tencentSecretKey;
  String tencentRegion;
  int tencentProjectId;
  List<String> panelAppIds; // 服务面板展示的应用 id 列表
  List<String> translateEnabledLangs; // 启用的翻译语言对（TranslateLang.name 列表）
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

  /// 向后兼容：LLM 日志开关 → 映射到 logCategories['llm'].console
  bool get llmLogEnabled => logCategories['llm']?.console ?? false;
  set llmLogEnabled(bool v) {
    final cur = logCategories['llm'] ?? const LogCategoryConfig();
    logCategories['llm'] = cur.copyWith(console: v);
  }

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
      logCategories: _parseLogCategories(json),
      appTheme: json['appTheme'] as String? ?? 'light',
      showTranslateLangSelector:
          json['showTranslateLangSelector'] as bool? ?? true,
      translationProvider: json['translationProvider'] as String? ?? 'llm',
      tencentSecretId: json['tencentSecretId'] as String? ?? '',
      tencentSecretKey: json['tencentSecretKey'] as String? ?? '',
      tencentRegion: json['tencentRegion'] as String? ?? 'ap-guangzhou',
      tencentProjectId: json['tencentProjectId'] as int? ?? 0,
      panelAppIds:
          (json['panelAppIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      translateEnabledLangs:
          (json['translateEnabledLangs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
      apiConfigs: configs,
    );
  }

  /// 从 JSON 解析 logCategories，兼容旧的 llmLogEnabled 字段
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
    // 从旧格式迁移：只有 llmLogEnabled 布尔值
    final oldLlmLog = json['llmLogEnabled'] as bool? ?? false;
    return {
      'system': const LogCategoryConfig(console: true, file: true),
      'llm': LogCategoryConfig(console: oldLlmLog, file: false),
    };
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'apiConfigs': apiConfigs.map((k, v) => MapEntry(k, v.toJson())),
    'logCategories': logCategories.map((k, v) => MapEntry(k, v.toJson())),
    'appTheme': appTheme,
    'showTranslateLangSelector': showTranslateLangSelector,
    'translationProvider': translationProvider,
    'tencentSecretId': tencentSecretId,
    'tencentSecretKey': tencentSecretKey,
    'tencentRegion': tencentRegion,
    'tencentProjectId': tencentProjectId,
    'panelAppIds': panelAppIds,
    'translateEnabledLangs': translateEnabledLangs,
  };
}

class SettingsService {
  SettingsService._();

  static Future<File> _file() async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby');
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
