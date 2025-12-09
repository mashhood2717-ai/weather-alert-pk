// lib/services/aqi_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// AQI forecast for a single day
class AqiForecast {
  final DateTime date;
  final int avgAqi;
  final double avgPm25;
  final double avgPm10;

  AqiForecast({
    required this.date,
    required this.avgAqi,
    required this.avgPm25,
    required this.avgPm10,
  });
}

/// Complete Air Quality data with current reading and forecast
class AirQualityData {
  final int usAqi;
  final double pm25;
  final double pm10;
  final DateTime timestamp;
  final List<AqiForecast> forecast;

  AirQualityData({
    required this.usAqi,
    required this.pm25,
    required this.pm10,
    required this.timestamp,
    required this.forecast,
  });
}

class AqiService {
  static const String _baseUrl =
      'https://air-quality-api.open-meteo.com/v1/air-quality';

  /// Get color for AQI value
  static Color getAqiColor(int aqi) {
    if (aqi <= 50) return const Color(0xFF00E400); // Green
    if (aqi <= 100) return const Color(0xFFFFFF00); // Yellow
    if (aqi <= 150) return const Color(0xFFFF7E00); // Orange
    if (aqi <= 200) return const Color(0xFFFF0000); // Red
    if (aqi <= 300) return const Color(0xFF8F3F97); // Purple
    return const Color(0xFF7E0023); // Maroon
  }

  /// Get classification string for AQI value
  static String getAqiClassification(int aqi) {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for Sensitive';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  /// Calculate AQI from PM2.5
  static int calculateAqiFromPm25(double pm25) {
    if (pm25 <= 12.0) return ((pm25 / 12.0) * 50).round();
    if (pm25 <= 35.4) return (50 + ((pm25 - 12.0) / 23.4) * 50).round();
    if (pm25 <= 55.4) return (100 + ((pm25 - 35.4) / 20.0) * 50).round();
    if (pm25 <= 150.4) return (150 + ((pm25 - 55.4) / 95.0) * 50).round();
    if (pm25 <= 250.4) return (200 + ((pm25 - 150.4) / 100.0) * 100).round();
    return (300 + ((pm25 - 250.4) / 150.0) * 100).round().clamp(0, 500);
  }

  /// Fetch complete air quality data with current and 5-day forecast
  static Future<AirQualityData?> fetchAirQuality(double lat, double lon) async {
    final url = '$_baseUrl?'
        'latitude=$lat&longitude=$lon'
        '&hourly=pm2_5,pm10'
        '&current=us_aqi,pm10,pm2_5'
        '&timezone=auto&forecast_days=5&timeformat=unixtime';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);

      // Parse current data
      final current = json['current'];
      if (current == null) return null;

      final timeValue = current['time'];
      DateTime timestamp;
      if (timeValue is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timeValue * 1000);
      } else {
        timestamp = DateTime.now();
      }

      final usAqi = _toInt(current['us_aqi']);
      final pm25 = _toDouble(current['pm2_5']);
      final pm10 = _toDouble(current['pm10']);

      // Parse hourly and aggregate to daily forecast
      final forecast = _parseDailyForecast(json);

      return AirQualityData(
        usAqi: usAqi,
        pm25: pm25,
        pm10: pm10,
        timestamp: timestamp,
        forecast: forecast,
      );
    } catch (e) {
      print('AQI Service Error: $e');
      return null;
    }
  }

  /// Parse hourly data and aggregate to daily forecast
  static List<AqiForecast> _parseDailyForecast(Map<String, dynamic> json) {
    final List<AqiForecast> forecast = [];

    try {
      final hourly = json['hourly'];
      if (hourly == null) return forecast;

      final times = hourly['time'] as List<dynamic>?;
      final pm25List = hourly['pm2_5'] as List<dynamic>?;
      final pm10List = hourly['pm10'] as List<dynamic>?;

      if (times == null || pm25List == null) return forecast;

      // Group by day and calculate averages
      final Map<String, Map<String, dynamic>> dailyData = {};

      for (int i = 0; i < times.length; i++) {
        final timeValue = times[i];
        DateTime time;
        if (timeValue is int) {
          time = DateTime.fromMillisecondsSinceEpoch(timeValue * 1000);
        } else {
          continue;
        }

        final dateKey =
            '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
        final pm25 = _toDouble(pm25List[i]);
        final pm10 = _toDouble(
            pm10List != null && pm10List.length > i ? pm10List[i] : 0);
        final aqi = calculateAqiFromPm25(pm25);

        if (!dailyData.containsKey(dateKey)) {
          dailyData[dateKey] = {
            'date': time,
            'totalAqi': aqi,
            'totalPm25': pm25,
            'totalPm10': pm10,
            'count': 1,
          };
        } else {
          final existing = dailyData[dateKey]!;
          existing['totalAqi'] = (existing['totalAqi'] as int) + aqi;
          existing['totalPm25'] = (existing['totalPm25'] as double) + pm25;
          existing['totalPm10'] = (existing['totalPm10'] as double) + pm10;
          existing['count'] = (existing['count'] as int) + 1;
        }
      }

      // Convert to list with averages and sort by date
      final sortedKeys = dailyData.keys.toList()..sort();
      for (final key in sortedKeys.take(5)) {
        final data = dailyData[key]!;
        final count = data['count'] as int;
        forecast.add(AqiForecast(
          date: data['date'] as DateTime,
          avgAqi: ((data['totalAqi'] as int) / count).round(),
          avgPm25: (data['totalPm25'] as double) / count,
          avgPm10: (data['totalPm10'] as double) / count,
        ));
      }
    } catch (e) {
      print('Parse daily AQI error: $e');
    }

    return forecast;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
