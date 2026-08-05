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
    this.balanceUrl = '',
    this.chatUrl = '',
    this.model = '',
    this.enableBalance = true,
  });

  String apiKey;
  String balanceUrl;
  String chatUrl;
  String model;
  bool enableBalance;

  factory PlatformApiConfig.fromJson(Map<String, dynamic> json) {
    return PlatformApiConfig(
      apiKey: json['apiKey'] as String? ?? '',
      balanceUrl: json['balanceUrl'] as String? ?? '',
      chatUrl: json['chatUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      enableBalance: json['enableBalance'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'apiKey': apiKey,
    'balanceUrl': balanceUrl,
    'chatUrl': chatUrl,
    'model': model,
    'enableBalance': enableBalance,
  };
}

class AppSettings {
  AppSettings({
    this.platform = 'deepseek',
    String apiKey = '',
    String balanceUrl = '',
    String chatUrl = '',
    this.currencySymbol = '¥',
    this.refreshInterval = 30,
    this.autoStart = false,
    this.language = 'zh',
    this.showVibePanel = true,
    this.enableClipboardMonitor = false,
    this.appTheme = 'light',
    this.agentChatPopupTheme = 'light',
    this.petStyle = 'colorful',
    this.menuHotkey = 'Alt+96',
    this.panelAppIds = const [],
    this.panelOrder = const [],
    this.hiddenPanels = const [],
    this.userName = '',
    this.userAvatarPath = '',
    this.menuBgImage = '',
    this.menuBgFilePath = '',
    this.menuWindowLeft = -1,
    this.menuWindowTop = -1,
    this.menuWindowHeight = -1,
    this.weatherApiId = '',
    this.weatherApiKey = '',
    this.weatherApiHost = 'devapi.qweather.com',
    this.weatherCity = '上海',
    this.weatherLastFetchDate = '',
    this.dailyQuoteType = '',
    this.dailyQuoteCountry = '',
    this.balanceRefreshInterval = 0,
    this.photoWallSwitchInterval = 30,
    this.carouselSwitchInterval = 12,
    this.showTranslateLangSelector = true,
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
               balanceUrl: balanceUrl.isEmpty
                   ? PlatformConfig.defaultBalanceUrl('deepseek')
                   : balanceUrl,
               chatUrl: chatUrl.isEmpty
                   ? PlatformConfig.defaultChatUrl('deepseek')
                   : chatUrl,
             ),
           },
       logCategories = logCategories ??
           {
             'system': const LogCategoryConfig(console: true, file: true),
             'weixin': const LogCategoryConfig(console: true, file: true),
             'llm': const LogCategoryConfig(console: true, file: false),
           };

  String platform;
  String currencySymbol;
  int refreshInterval;
  bool autoStart;
  String language;
  bool showVibePanel;
  bool enableClipboardMonitor;
  Map<String, LogCategoryConfig> logCategories;
  String appTheme;
  String agentChatPopupTheme;
  String petStyle;
  String menuHotkey;
  List<String> panelAppIds;
  List<String> panelOrder;
  List<String> hiddenPanels;
  String userName;
  String userAvatarPath;
  String menuBgImage;
  String menuBgFilePath;
  double menuWindowLeft;
  double menuWindowTop;
  double menuWindowHeight;
  String weatherApiId;
  String weatherApiKey;
  String weatherApiHost;
  String weatherCity;
  String weatherLastFetchDate; // 格式: "2026-07-29"
  String dailyQuoteType; // 每日一言类型：'' | '诗词' | '名言' | '歌词' | '歇后语' | '俚语' | '短笑话'
  String dailyQuoteCountry; // 每日一言国家：'' | '中国' | '外国'
  int balanceRefreshInterval; // 余额刷新频率（秒）：0=每天, 21600=6小时, 10800=3小时
  int photoWallSwitchInterval; // 照片墙切换频率（秒）：10, 30, 60, 600, 3600
  int carouselSwitchInterval; // 轮播图切换频率（秒）：5, 12, 30, 60, 300
  bool showTranslateLangSelector; // 是否显示翻译面板的语言选择器
  List<String> translateEnabledLangs; // 启用的翻译语言对（TranslateLang.name 列表）
  Map<String, PlatformApiConfig> apiConfigs;

  /// 当前平台的便捷访问器
  PlatformApiConfig get currentApi => apiConfigs.putIfAbsent(
    platform,
    () => PlatformApiConfig(
      balanceUrl: PlatformConfig.defaultBalanceUrl(platform),
      chatUrl: PlatformConfig.defaultChatUrl(platform),
    ),
  );

  String get apiKey => currentApi.apiKey;
  set apiKey(String v) => currentApi.apiKey = v;

  String get balanceUrl => currentApi.balanceUrl;
  set balanceUrl(String v) => currentApi.balanceUrl = v;

  String get chatUrl => currentApi.chatUrl;
  set chatUrl(String v) => currentApi.chatUrl = v;

  String get model => currentApi.model;
  set model(String v) => currentApi.model = v;

  bool get enableBalance => currentApi.enableBalance;
  set enableBalance(bool v) => currentApi.enableBalance = v;

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
      // 兼容旧格式：顶层 apiKey/balanceUrl/chatUrl → 当前平台
      configs = {
        platform: PlatformApiConfig(
          apiKey: json['apiKey'] as String? ?? '',
          balanceUrl: json['balanceUrl'] as String? ?? '',
          chatUrl: json['chatUrl'] as String? ?? '',
        ),
      };
    }

    // 确保当前平台在 configs 中存在
    configs.putIfAbsent(
      platform,
      () => PlatformApiConfig(
        balanceUrl: PlatformConfig.defaultBalanceUrl(platform),
        chatUrl: PlatformConfig.defaultChatUrl(platform),
      ),
    );

    return AppSettings(
      platform: platform,
      currencySymbol: json['currencySymbol'] as String? ?? '¥',
      refreshInterval: json['refreshInterval'] as int? ?? 30,
      autoStart: json['autoStart'] as bool? ?? false,
      language: json['language'] as String? ?? 'zh',
      showVibePanel: json['showVibePanel'] as bool? ?? true,
      enableClipboardMonitor: json['enableClipboardMonitor'] as bool? ?? false,
      logCategories: _parseLogCategories(json),
      appTheme: json['appTheme'] as String? ?? 'light',
      agentChatPopupTheme: json['agentChatPopupTheme'] as String? ?? 'light',
      petStyle: json['petStyle'] as String? ?? 'colorful',
      menuHotkey: json['menuHotkey'] as String? ?? 'Alt+96',
      panelAppIds:
          (json['panelAppIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      panelOrder:
          (json['panelOrder'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      hiddenPanels:
          (json['hiddenPanels'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      userName: json['userName'] as String? ?? '',
      userAvatarPath: json['userAvatarPath'] as String? ?? '',
      menuBgImage: json['menuBgImage'] as String? ?? '',
      menuBgFilePath: json['menuBgFilePath'] as String? ?? '',
      menuWindowLeft: (json['menuWindowLeft'] as num?)?.toDouble() ?? -1,
      menuWindowTop: (json['menuWindowTop'] as num?)?.toDouble() ?? -1,
      menuWindowHeight: (json['menuWindowHeight'] as num?)?.toDouble() ?? -1,
      weatherApiId: json['weatherApiId'] as String? ?? '',
      weatherApiKey: json['weatherApiKey'] as String? ?? '',
      weatherApiHost: json['weatherApiHost'] as String? ?? 'devapi.qweather.com',
      weatherCity: json['weatherCity'] as String? ?? '上海',
      weatherLastFetchDate: json['weatherLastFetchDate'] as String? ?? '',
      dailyQuoteType: json['dailyQuoteType'] as String? ?? '',
      dailyQuoteCountry: json['dailyQuoteCountry'] as String? ?? '',
      balanceRefreshInterval: json['balanceRefreshInterval'] as int? ?? 0,
      photoWallSwitchInterval: json['photoWallSwitchInterval'] as int? ?? 30,
      carouselSwitchInterval: json['carouselSwitchInterval'] as int? ?? 12,
      showTranslateLangSelector:
          json['showTranslateLangSelector'] as bool? ?? true,
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
      'weixin': const LogCategoryConfig(console: true, file: true),
      'llm': LogCategoryConfig(console: oldLlmLog, file: false),
    };
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'apiConfigs': apiConfigs.map((k, v) => MapEntry(k, v.toJson())),
    'currencySymbol': currencySymbol,
    'refreshInterval': refreshInterval,
    'autoStart': autoStart,
    'language': language,
    'showVibePanel': showVibePanel,
    'enableClipboardMonitor': enableClipboardMonitor,
    'logCategories': logCategories.map((k, v) => MapEntry(k, v.toJson())),
    'appTheme': appTheme,
    'agentChatPopupTheme': agentChatPopupTheme,
    'petStyle': petStyle,
    'menuHotkey': menuHotkey,
    'panelAppIds': panelAppIds,
    'panelOrder': panelOrder,
    'hiddenPanels': hiddenPanels,
    'userName': userName,
    'userAvatarPath': userAvatarPath,
    'menuBgImage': menuBgImage,
    'menuBgFilePath': menuBgFilePath,
    'menuWindowLeft': menuWindowLeft,
    'menuWindowTop': menuWindowTop,
    'menuWindowHeight': menuWindowHeight,
    'weatherApiId': weatherApiId,
    'weatherApiKey': weatherApiKey,
    'weatherApiHost': weatherApiHost,
    'weatherCity': weatherCity,
    'weatherLastFetchDate': weatherLastFetchDate,
    'dailyQuoteType': dailyQuoteType,
    'dailyQuoteCountry': dailyQuoteCountry,
    'balanceRefreshInterval': balanceRefreshInterval,
    'photoWallSwitchInterval': photoWallSwitchInterval,
    'carouselSwitchInterval': carouselSwitchInterval,
    'showTranslateLangSelector': showTranslateLangSelector,
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

  /// 头像存储路径（~/.orbby/user/user_avatar_`<timestamp>`.png）
  static Future<String> avatarFilePath() async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby/user');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}/user_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
  }

  /// 菜单背景图存储路径（~/.orbby/user/menu_bg_`<timestamp>`.`<ext>`）
  static Future<String> menuBgFilePath(String extension) async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby/user');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}/menu_bg_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }
}
