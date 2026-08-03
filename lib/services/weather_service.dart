import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;

import '../config/settings.dart';

/// 天气数据模型
class WeatherData {
  final String location;
  final String weather;
  final String temperature;
  final String wind;
  final String suggestion;

  const WeatherData({
    required this.location,
    required this.weather,
    required this.temperature,
    required this.wind,
    required this.suggestion,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      location: json['location'] as String? ?? '',
      weather: json['weather'] as String? ?? '未知',
      temperature: json['temperature'] as String? ?? '--°C',
      wind: json['wind'] as String? ?? '未知',
      suggestion: json['suggestion'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'location': location,
    'weather': weather,
    'temperature': temperature,
    'wind': wind,
    'suggestion': suggestion,
  };
}

/// 天气服务 - 支持和风天气 API v7
class WeatherService {
  /// 从和风天气 API 获取天气数据
  static Future<WeatherData> fetchFromQWeather({
    required String apiKey,
    required String apiHost,
    required String city,
  }) async {
    // 使用 API Key 认证
    final headers = {'X-QW-Api-Key': apiKey};

    // 1. 先获取城市 ID（GeoAPI v2 需要认证）
    final geoUrl = Uri.parse(
      'https://$apiHost/geo/v2/city/lookup?location=$city&range=cn',
    );

    final geoResponse = await http
        .get(geoUrl, headers: headers)
        .timeout(const Duration(seconds: 10));

    if (geoResponse.statusCode != 200) {
      throw Exception('城市查询失败: ${geoResponse.statusCode}');
    }

    final geoData = jsonDecode(geoResponse.body) as Map<String, dynamic>;
    if (geoData['code'] != '200') {
      throw Exception('城市查询失败: ${geoData['code']}');
    }

    final locations = geoData['location'] as List<dynamic>?;
    if (locations == null || locations.isEmpty) {
      throw Exception('未找到城市: $city');
    }

    final locationId = locations[0]['id'] as String;
    final locationName = locations[0]['name'] as String? ?? city;

    // 2. 获取实时天气（使用 Bearer token）
    final weatherUrl = Uri.parse(
      'https://$apiHost/v7/weather/now?location=$locationId',
    );

    final weatherResponse = await http
        .get(weatherUrl, headers: headers)
        .timeout(const Duration(seconds: 10));

    if (weatherResponse.statusCode != 200) {
      throw Exception('天气查询失败: ${weatherResponse.statusCode}');
    }

    final weatherData =
        jsonDecode(weatherResponse.body) as Map<String, dynamic>;
    if (weatherData['code'] != '200') {
      throw Exception('天气查询失败: ${weatherData['code']}');
    }

    final now = weatherData['now'] as Map<String, dynamic>;

    // 3. 获取生活指数（穿衣建议）
    String suggestion = '';
    try {
      final indicesUrl = Uri.parse(
        'https://$apiHost/v7/indices/1d?type=3&location=$locationId',
      );

      final indicesResponse = await http
          .get(indicesUrl, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (indicesResponse.statusCode == 200) {
        final indicesData =
            jsonDecode(indicesResponse.body) as Map<String, dynamic>;
        if (indicesData['code'] == '200') {
          final daily = indicesData['daily'] as List<dynamic>?;
          if (daily != null && daily.isNotEmpty) {
            suggestion = daily[0]['text'] as String? ?? '';
          }
        }
      }
    } catch (e) {}

    // 构建温度范围
    final temp = now['temp'] as String? ?? '--';
    final feelsLike = now['feelsLike'] as String? ?? '--';
    final temperature = '$temp°C (体感$feelsLike°C)';

    return WeatherData(
      location: locationName,
      weather: now['text'] as String? ?? '未知',
      temperature: temperature,
      wind: '${now['windDir'] ?? ''} ${now['windScale'] ?? ''}级',
      suggestion: suggestion.isNotEmpty ? suggestion : '暂无建议',
    );
  }

  /// 便捷入口
  static Future<WeatherData> fetch({
    String? city,
    String? apiKey,
    String? apiHost,
  }) async {
    final settings = await SettingsService.load();
    final actualCity = city ?? settings.weatherCity;
    final actualApiKey = apiKey ?? settings.weatherApiKey;
    final actualApiHost = apiHost ?? settings.weatherApiHost;

    if (actualApiKey.isEmpty) {
      throw Exception('请先在设置中配置天气 API Key');
    }

    return fetchFromQWeather(
      apiKey: actualApiKey,
      apiHost: actualApiHost,
      city: actualCity,
    );
  }
}
