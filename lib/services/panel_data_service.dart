// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import '../config/settings.dart';
import '../services/balance_service.dart';
import '../services/daily_quote_service.dart';
import '../services/favorites_service.dart';
import '../services/news_service.dart';
import '../services/panel_cache.dart';
import '../services/photo_wall_service.dart';
import '../services/schedule_service.dart';
import '../services/script_service.dart';
import '../services/todo_service.dart';
import '../services/weather_service.dart';
import '../widgets/app_square_panel.dart' show AppConfig, AppInfo;

/// 面板数据集中式服务
///
/// 所有面板数据的 **唯一入口**——面板不应直接调用各业务 Service，
/// 而是通过本服务的 refresh 方法获取数据。数据统一写入 [PanelCache]，
/// 面板通过监听 [PanelCache] 自动更新 UI。
class PanelDataService {
  PanelDataService._();

  // ---- DailyQuote -------------------------------------------------------

  static Future<void> refreshDailyQuote() async {
    try {
      final settings = await SettingsService.load();
      final data = await DailyQuoteService.fetchQuote(
        type: settings.dailyQuoteType,
        country: settings.dailyQuoteCountry,
      );
      PanelCache.set('daily_quote', data);
    } catch (e) {
      print('[PanelData] daily_quote refresh failed: $e');
    }
  }

  // ---- Weather ----------------------------------------------------------

  static Future<void> refreshWeather() async {
    try {
      final settings = await SettingsService.load();
      if (settings.weatherApiKey.isEmpty || settings.weatherCity.isEmpty)
        return;

      final data = await WeatherService.fetch();

      PanelCache.set('weather_data', data);
      PanelCache.set('weather_result', jsonEncode(data.toJson()));

      final today = DateTime.now().toString().substring(0, 10);
      settings.weatherLastFetchDate = today;
      await SettingsService.save(settings);
    } catch (e) {
      print('[PanelData] weather refresh failed: $e');
    }
  }

  // ---- Balance ----------------------------------------------------------

  static Future<void> refreshBalance() async {
    try {
      final settings = await SettingsService.load();
      if (settings.apiKey.isEmpty) {
        PanelCache.set('balance_connected', false);
        return;
      }

      final isConnected = await BalanceService.testConnectivity();
      PanelCache.set('balance_connected', isConnected);

      if (isConnected) {
        final balance = await BalanceService.fetchBalance();
        PanelCache.set('balance_info', balance);
      } else {
        PanelCache.set(
          'balance_info',
          BalanceInfo(
            isAvailable: true,
            totalBalance: 0,
            grantedBalance: 0,
            toppedUpBalance: 0,
            currency: '0',
          ),
        );
      }
    } catch (e) {
      print('[PanelData] balance refresh failed: $e');
    }
  }

  // ---- News -------------------------------------------------------------

  static Future<void> refreshNews() async {
    try {
      await NewsCache.instance.init();
    } catch (e) {
      print('[PanelData] news refresh failed: $e');
    }
  }

  // ---- PhotoWall --------------------------------------------------------

  static Future<void> refreshPhotoWall() async {
    try {
      final photos = await PhotoWallService.loadPhotos();
      final valid = photos.where((p) => File(p).existsSync()).toList();
      if (valid.length != photos.length) {
        await PhotoWallService.savePhotos(valid);
      }
      PanelCache.set('photo_wall_photos', valid);
    } catch (e) {
      print('[PanelData] photo_wall refresh failed: $e');
    }
  }

  // ---- Schedule ---------------------------------------------------------

  static Future<void> refreshSchedule() async {
    try {
      final items = await ScheduleService.loadRecent(limit: 5);
      PanelCache.set('schedule_items', items);
    } catch (e) {
      print('[PanelData] schedule refresh failed: $e');
    }
  }

  // ---- Todo -------------------------------------------------------------

  static Future<void> refreshTodo() async {
    try {
      final todos = await TodoService.loadAll();
      PanelCache.set('todo_items', todos);
    } catch (e) {
      print('[PanelData] todo refresh failed: $e');
    }
  }

  // ---- Favorites --------------------------------------------------------

  static Future<void> refreshFavorites() async {
    try {
      final folders = await FavoritesService.loadFolders();
      final allItems = await FavoritesService.loadAllItems();
      final uncategorizedCount = await FavoritesService.uncategorizedCount();
      PanelCache.set('favorites_data', {
        'folders': folders,
        'allItems': allItems,
        'uncategorizedCount': uncategorizedCount,
      });
    } catch (e) {
      print('[PanelData] favorites refresh failed: $e');
    }
  }

  // ---- Apps -------------------------------------------------------------

  static Future<void> refreshApps() async {
    try {
      final settings = await SettingsService.load();
      final custom = AppConfig.loadCustomApps();
      final system = AppConfig.loadSystemApps();
      final allApps = [...custom, ...system];

      List<AppInfo> apps;
      if (settings.panelAppIds.isNotEmpty) {
        apps = settings.panelAppIds
            .map((id) => allApps.where((a) => a.id == id))
            .expand((m) => m)
            .take(8)
            .toList();
      } else {
        apps = allApps.take(8).toList();
      }
      PanelCache.set('app_square_apps', apps);
    } catch (e) {
      print('[PanelData] apps refresh failed: $e');
    }
  }

  // ---- Scripts ----------------------------------------------------------

  static Future<void> refreshScripts() async {
    try {
      final scripts = await ScriptService.loadAll();
      PanelCache.set('script_items', scripts);
    } catch (e) {
      print('[PanelData] scripts refresh failed: $e');
    }
  }
}
