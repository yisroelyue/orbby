import 'dart:convert';
import 'dart:io';

import 'platform.dart';

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
    this.showBalancePanel = true,
    this.showTranslatePanel = true,
    this.showTodoPanel = true,
    this.showFavoritesPanel = true,
    this.showAppSquarePanel = true,
    this.showVibePanel = true,
    this.showPhotoWallPanel = true,
    this.showAgentChatPanel = true,
    this.showControlPanel = true,
    this.showWeatherPanel = true,
    this.showNewsPanel = true,
    this.showScriptPanel = true,
    this.showSchedulePanel = true,
    this.showDailyQuotePanel = true,
    this.enableClipboardMonitor = false,
    this.menuAutoHideDelay = 3.0,
    this.appTheme = 'light',
    this.agentChatPopupTheme = 'light',
    this.petStyle = 'colorful',
    this.menuHotkey = 'Alt+96',
    this.panelAppIds = const [],
    this.panelOrder = const [],
    this.hiddenPanels = const [],
    this.userName = '',
    this.userAvatarPath = '',
    this.menuBgImage = 'assets/png/menuBg/11826657.jpg',
    Map<String, PlatformApiConfig>? apiConfigs,
  }) : apiConfigs = apiConfigs ?? {
          'deepseek': PlatformApiConfig(
            apiKey: apiKey,
            balanceUrl: balanceUrl.isEmpty
                ? PlatformConfig.defaultBalanceUrl('deepseek')
                : balanceUrl,
            chatUrl: chatUrl.isEmpty
                ? PlatformConfig.defaultChatUrl('deepseek')
                : chatUrl,
          ),
        };

  String platform;
  String currencySymbol;
  int refreshInterval;
  bool autoStart;
  String language;
  bool showBalancePanel;
  bool showTranslatePanel;
  bool showTodoPanel;
  bool showFavoritesPanel;
  bool showAppSquarePanel;
  bool showVibePanel;
  bool showPhotoWallPanel;
  bool showAgentChatPanel;
  bool showControlPanel;
  bool showWeatherPanel;
  bool showNewsPanel;
  bool showScriptPanel;
  bool showSchedulePanel;
  bool showDailyQuotePanel;
  bool enableClipboardMonitor;
  double menuAutoHideDelay;
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
  Map<String, PlatformApiConfig> apiConfigs;

  /// 当前平台的便捷访问器
  PlatformApiConfig get currentApi =>
      apiConfigs.putIfAbsent(
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

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final platform = json['platform'] as String? ?? 'deepseek';

    // 解析 apiConfigs，若不存在则从旧格式迁移
    Map<String, PlatformApiConfig> configs;
    final rawConfigs = json['apiConfigs'] as Map<String, dynamic>?;
    if (rawConfigs != null) {
      configs = rawConfigs.map(
        (k, v) => MapEntry(k, PlatformApiConfig.fromJson(v as Map<String, dynamic>)),
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
      showBalancePanel: json['showBalancePanel'] as bool? ?? true,
      showTranslatePanel: json['showTranslatePanel'] as bool? ?? true,
      showTodoPanel: json['showTodoPanel'] as bool? ?? true,
      showFavoritesPanel: json['showFavoritesPanel'] as bool? ?? true,
      showAppSquarePanel: json['showAppSquarePanel'] as bool? ?? true,
      showVibePanel: json['showVibePanel'] as bool? ?? true,
      showPhotoWallPanel: json['showPhotoWallPanel'] as bool? ?? true,
      showAgentChatPanel: json['showAgentChatPanel'] as bool? ?? true,
      showControlPanel: json['showControlPanel'] as bool? ?? true,
      showWeatherPanel: json['showWeatherPanel'] as bool? ?? true,
      showNewsPanel: json['showNewsPanel'] as bool? ?? true,
      showScriptPanel: json['showScriptPanel'] as bool? ?? true,
      showSchedulePanel: json['showSchedulePanel'] as bool? ?? true,
      showDailyQuotePanel: json['showDailyQuotePanel'] as bool? ?? true,
      enableClipboardMonitor: json['enableClipboardMonitor'] as bool? ?? false,
      menuAutoHideDelay: (json['menuAutoHideDelay'] as num?)?.toDouble() ?? 3.0,
      appTheme: json['appTheme'] as String? ?? 'light',
      agentChatPopupTheme: json['agentChatPopupTheme'] as String? ?? 'light',
      petStyle: json['petStyle'] as String? ?? 'colorful',
      menuHotkey: json['menuHotkey'] as String? ?? 'Alt+96',
      panelAppIds: (json['panelAppIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      panelOrder: (json['panelOrder'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      hiddenPanels: (json['hiddenPanels'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      userName: json['userName'] as String? ?? '',
      userAvatarPath: json['userAvatarPath'] as String? ?? '',
      menuBgImage: json['menuBgImage'] as String? ?? 'assets/png/menuBg/11826657.jpg',
      apiConfigs: configs,
    );
  }

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'apiConfigs': apiConfigs.map((k, v) => MapEntry(k, v.toJson())),
        'currencySymbol': currencySymbol,
        'refreshInterval': refreshInterval,
        'autoStart': autoStart,
        'language': language,
        'showBalancePanel': showBalancePanel,
        'showTranslatePanel': showTranslatePanel,
        'showTodoPanel': showTodoPanel,
        'showFavoritesPanel': showFavoritesPanel,
        'showAppSquarePanel': showAppSquarePanel,
        'showVibePanel': showVibePanel,
        'showPhotoWallPanel': showPhotoWallPanel,
        'showAgentChatPanel': showAgentChatPanel,
        'showControlPanel': showControlPanel,
        'showWeatherPanel': showWeatherPanel,
        'showNewsPanel': showNewsPanel,
        'showScriptPanel': showScriptPanel,
        'showSchedulePanel': showSchedulePanel,
        'showDailyQuotePanel': showDailyQuotePanel,
        'enableClipboardMonitor': enableClipboardMonitor,
        'menuAutoHideDelay': menuAutoHideDelay,
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
      };
}

class SettingsService {
  SettingsService._();

  static Future<File> _file() async {
    final home = Platform.environment['USERPROFILE'] ??
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

  /// 头像存储路径（~/.orbby/user/user_avatar_<timestamp>.png）
  static Future<String> avatarFilePath() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dir = Directory('$home/.orbby/user');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}/user_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
  }
}
