// lib/services/weather_monitor_service.dart
// Local weather monitoring - checks conditions and triggers alerts without Cloud Functions

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_alert.dart';
import '../metar_service.dart';
import 'alert_storage_service.dart';
import 'notification_service.dart';
import 'weather_controller.dart';

class WeatherMonitorService {
  static final WeatherMonitorService _instance =
      WeatherMonitorService._internal();
  factory WeatherMonitorService() => _instance;
  WeatherMonitorService._internal();

  Timer? _monitorTimer;
  final WeatherController _weatherController = WeatherController();
  final NotificationService _notificationService = NotificationService();
  final AlertStorageService _alertStorage = AlertStorageService();

  // City to ICAO mapping for METAR data
  static const Map<String, String> _cityToIcao = {
    'islamabad': 'OPIS',
    'rawalpindi': 'OPIS',
    'lahore': 'OPLA',
    'karachi': 'OPKC',
    'faisalabad': 'OPFA',
    'multan': 'OPMT',
    'peshawar': 'OPPS',
    'quetta': 'OPQT',
    'sialkot': 'OPST',
    'gwadar': 'OPGD',
    'hyderabad': 'OPKD',
  };

  // METAR condition codes that trigger alerts
  static const Map<String, Map<String, String>> _metarAlertConditions = {
    'TS': {
      'severity': 'high',
      'title': '⛈️ Thunderstorm',
      'desc': 'Thunderstorm activity detected'
    },
    'TSRA': {
      'severity': 'high',
      'title': '⛈️ Thunderstorm + Rain',
      'desc': 'Thunderstorm with rain'
    },
    'TSGR': {
      'severity': 'extreme',
      'title': '⛈️ Thunderstorm + Hail',
      'desc': 'Thunderstorm with hail'
    },
    '+RA': {
      'severity': 'high',
      'title': '🌧️ Heavy Rain',
      'desc': 'Heavy rainfall - flooding possible'
    },
    'FG': {
      'severity': 'high',
      'title': '🌫️ Dense Fog',
      'desc': 'Dense fog - very low visibility'
    },
    'BR': {
      'severity': 'medium',
      'title': '🌫️ Mist',
      'desc': 'Mist reducing visibility'
    },
    'HZ': {
      'severity': 'medium',
      'title': '🌫️ Haze',
      'desc': 'Haze reducing visibility'
    },
    'FU': {
      'severity': 'high',
      'title': '💨 Smoke',
      'desc': 'Smoke in the area'
    },
    'DU': {'severity': 'high', 'title': '🌪️ Dust', 'desc': 'Widespread dust'},
    'SA': {'severity': 'high', 'title': '🌪️ Sand', 'desc': 'Sand in the air'},
    'DS': {
      'severity': 'extreme',
      'title': '🌪️ Dust Storm',
      'desc': 'Dust storm - stay indoors!'
    },
    'SS': {
      'severity': 'extreme',
      'title': '🌪️ Sand Storm',
      'desc': 'Sand storm - stay indoors!'
    },
    'SN': {'severity': 'high', 'title': '❄️ Snow', 'desc': 'Snowfall detected'},
    '+SN': {
      'severity': 'extreme',
      'title': '❄️ Heavy Snow',
      'desc': 'Heavy snowfall'
    },
    'FZRA': {
      'severity': 'extreme',
      'title': '🧊 Freezing Rain',
      'desc': 'Freezing rain - dangerous conditions'
    },
    'GR': {
      'severity': 'extreme',
      'title': '🧊 Hail',
      'desc': 'Hail detected - take cover'
    },
    'SQ': {
      'severity': 'high',
      'title': '💨 Squall',
      'desc': 'Squall - sudden strong winds'
    },
    'FC': {
      'severity': 'extreme',
      'title': '🌪️ Funnel Cloud',
      'desc': 'Funnel cloud/tornado - seek shelter!'
    },
  };

  // Thresholds for alerts (defaults, can be overridden by user settings)
  static const double defaultTempHighThreshold = 45.0; // Extreme heat
  static const double defaultTempLowThreshold = 5.0; // Cold warning
  static const double defaultWindSpeedThreshold = 50.0; // Strong winds km/h
  static const double defaultRainThreshold = 20.0; // Heavy rain mm
  static const double defaultVisibilityThreshold = 2.0; // Low visibility km
  static const int uvThreshold = 8; // High UV

  // Key for storing last alert times to prevent spam
  static const String _lastAlertKey = 'last_weather_alert_';
  static const Duration _alertCooldown =
      Duration(hours: 3); // Don't repeat same alert within 3 hours

  /// Start monitoring weather for subscribed cities
  Future<void> startMonitoring() async {
    // Check immediately on start
    await checkWeatherConditions();

    // Battery optimization: check every 45 minutes (vs 30 min)
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(minutes: 45), (_) {
      checkWeatherConditions();
    });

    debugPrint('Weather monitoring started (45 min interval)');
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    debugPrint('Weather monitoring stopped');
  }

  /// Check weather for all subscribed cities
  Future<void> checkWeatherConditions() async {
    final prefs = await SharedPreferences.getInstance();
    final subscribedCities = _getSubscribedCities(prefs);

    if (subscribedCities.isEmpty) {
      debugPrint('No cities subscribed for monitoring');
      return;
    }

    debugPrint('Checking weather for: ${subscribedCities.join(", ")}');

    for (final city in subscribedCities) {
      try {
        await _checkCityWeather(city, prefs);
      } catch (e) {
        debugPrint('Error checking weather for $city: $e');
      }
    }
  }

  List<String> _getSubscribedCities(SharedPreferences prefs) {
    // Get subscribed cities from the same key used by AlertStorageService
    return prefs.getStringList('subscribed_cities') ?? [];
  }

  Future<void> _checkCityWeather(String city, SharedPreferences prefs) async {
    // Load user-configured thresholds
    final tempHighThreshold =
        prefs.getDouble('threshold_temp_high') ?? defaultTempHighThreshold;
    final tempLowThreshold =
        prefs.getDouble('threshold_temp_low') ?? defaultTempLowThreshold;
    final windSpeedThreshold =
        prefs.getDouble('threshold_wind') ?? defaultWindSpeedThreshold;
    final visibilityThreshold =
        prefs.getDouble('threshold_visibility') ?? defaultVisibilityThreshold;

    debugPrint('=== Checking $city ===');
    debugPrint(
        'Thresholds - Heat: >$tempHighThreshold°C, Cold: <$tempLowThreshold°C, Wind: >$windSpeedThreshold km/h');

    // Fetch current weather
    await _weatherController.loadByCity(city);
    final current = _weatherController.current.value;

    if (current == null) {
      debugPrint('No weather data for $city');
      return;
    }

    debugPrint(
        'Current temp in $city: ${current.tempC}°C, Wind: ${current.windKph} km/h');

    final alerts = <Map<String, dynamic>>[];

    // Check extreme heat
    if (current.tempC >= tempHighThreshold) {
      debugPrint(
          '🔥 ALERT: Heat threshold exceeded! ${current.tempC} >= $tempHighThreshold');
      alerts.add({
        'type': 'extreme_heat',
        'severity': 'extreme',
        'title': '🔥 Extreme Heat - $city',
        'body':
            'Temperature: ${current.tempC.toStringAsFixed(1)}°C. Stay indoors and hydrated!',
      });
    }

    // Check cold weather
    if (current.tempC <= tempLowThreshold) {
      debugPrint(
          '❄️ ALERT: Cold threshold met! ${current.tempC} <= $tempLowThreshold');
      alerts.add({
        'type': 'cold',
        'severity': 'high',
        'title': '❄️ Cold Weather - $city',
        'body':
            'Temperature: ${current.tempC.toStringAsFixed(1)}°C. Bundle up and stay warm!',
      });
    }

    // Check strong winds
    if (current.windKph >= windSpeedThreshold) {
      alerts.add({
        'type': 'strong_wind',
        'severity': 'high',
        'title': '💨 Strong Winds - $city',
        'body':
            'Wind speed: ${current.windKph.toStringAsFixed(0)} km/h. Secure loose objects!',
      });
    }

    // Check low visibility
    final visKm = current.visKm;
    if (visKm != null && visKm <= visibilityThreshold) {
      alerts.add({
        'type': 'low_visibility',
        'severity': 'medium',
        'title': '🌫️ Low Visibility - $city',
        'body': 'Visibility: ${visKm.toStringAsFixed(1)} km. Drive carefully!',
      });
    }

    // Check condition text for severe weather
    final condition = current.condition.toLowerCase();
    if (condition.contains('thunder') || condition.contains('storm')) {
      alerts.add({
        'type': 'thunderstorm',
        'severity': 'high',
        'title': '⛈️ Thunderstorm - $city',
        'body': 'Thunderstorm activity detected. Stay indoors!',
      });
    }

    if (condition.contains('dust') || condition.contains('sand')) {
      alerts.add({
        'type': 'dust_storm',
        'severity': 'high',
        'title': '🌪️ Dust Storm - $city',
        'body': 'Dust storm warning. Close windows and stay indoors!',
      });
    }

    if (condition.contains('heavy rain') || condition.contains('torrential')) {
      alerts.add({
        'type': 'heavy_rain',
        'severity': 'high',
        'title': '🌧️ Heavy Rain - $city',
        'body': 'Heavy rainfall expected. Watch for flooding!',
      });
    }

    // ========================================
    // METAR-BASED ALERTS (More accurate for airports)
    // ========================================
    await _checkMetarAlerts(
        city, alerts, visibilityThreshold, windSpeedThreshold);

    // Send alerts that haven't been sent recently
    for (final alertData in alerts) {
      await _sendAlertIfNotRecent(alertData, city, prefs);
    }
  }

  /// Check METAR data for cities with airports
  Future<void> _checkMetarAlerts(
    String city,
    List<Map<String, dynamic>> alerts,
    double visibilityThreshold,
    double windSpeedThreshold,
  ) async {
    // Get ICAO code for the city
    final icao = _cityToIcao[city.toLowerCase()];
    if (icao == null) {
      debugPrint('No ICAO code for $city - skipping METAR check');
      return;
    }

    try {
      final metar = await fetchMetar(icao);
      if (metar == null) {
        debugPrint('No METAR data for $icao');
        return;
      }

      debugPrint(
          'METAR for $city ($icao): ${metar['condition_code']} - ${metar['raw_text']}');

      // Check METAR condition code for severe weather
      final condCode = metar['condition_code']?.toString().toUpperCase() ?? '';

      // Check against known severe conditions
      for (final entry in _metarAlertConditions.entries) {
        if (condCode.contains(entry.key)) {
          final alertInfo = entry.value;
          // Avoid duplicate alerts of same type
          final existingTypes = alerts.map((a) => a['type']).toSet();
          final alertType = 'metar_${entry.key.toLowerCase()}';

          if (!existingTypes.contains(alertType)) {
            alerts.add({
              'type': alertType,
              'severity': alertInfo['severity']!,
              'title': '${alertInfo['title']} - $city',
              'body': '${alertInfo['desc']}. (METAR: $icao)',
            });
          }
        }
      }

      // Check METAR visibility (more accurate than WeatherAPI)
      final visKmStr = metar['visibility_km']?.toString();
      if (visKmStr != null && visKmStr != '--') {
        final visKm = double.tryParse(visKmStr);
        if (visKm != null && visKm <= visibilityThreshold) {
          final existingTypes = alerts.map((a) => a['type']).toSet();
          if (!existingTypes.contains('low_visibility') &&
              !existingTypes.contains('metar_visibility')) {
            alerts.add({
              'type': 'metar_visibility',
              'severity': visKm < 1 ? 'high' : 'medium',
              'title': '🌫️ Low Visibility - $city',
              'body':
                  'METAR reports visibility: ${visKm.toStringAsFixed(1)} km. Drive carefully!',
            });
          }
        }
      }

      // Check METAR wind (more accurate)
      final windKphStr = metar['wind_kph']?.toString();
      if (windKphStr != null && windKphStr != '--') {
        final windKph = double.tryParse(windKphStr);
        if (windKph != null && windKph >= windSpeedThreshold) {
          final existingTypes = alerts.map((a) => a['type']).toSet();
          if (!existingTypes.contains('strong_wind') &&
              !existingTypes.contains('metar_wind')) {
            alerts.add({
              'type': 'metar_wind',
              'severity': windKph >= 80 ? 'extreme' : 'high',
              'title': '💨 Strong Winds - $city',
              'body':
                  'METAR reports wind: ${windKph.toStringAsFixed(0)} km/h. Secure loose objects!',
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching METAR for $city: $e');
    }
  }

  Future<void> _sendAlertIfNotRecent(
    Map<String, dynamic> alertData,
    String city,
    SharedPreferences prefs,
  ) async {
    final alertType = alertData['type'] as String;
    final key = '$_lastAlertKey${city}_$alertType';

    final lastAlertTime = prefs.getInt(key);
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check if we've sent this type of alert recently
    if (lastAlertTime != null) {
      final elapsed = Duration(milliseconds: now - lastAlertTime);
      if (elapsed < _alertCooldown) {
        debugPrint(
            'Skipping $alertType for $city (cooldown: ${_alertCooldown.inHours - elapsed.inHours}h remaining)');
        return;
      }
    }

    // Save alert to storage
    final alert = WeatherAlert(
      id: '${city}_${alertType}_$now',
      title: alertData['title'] as String,
      body: alertData['body'] as String,
      city: city,
      severity: alertData['severity'] as String,
      receivedAt: DateTime.now(),
      data: {'type': alertType, 'source': 'local_monitor'},
    );
    await _alertStorage.saveAlert(alert);

    // Show notification
    await _notificationService.showWeatherAlert(
      title: alertData['title'] as String,
      body: alertData['body'] as String,
      severity: alertData['severity'] as String,
      payload: '{"city": "$city", "type": "$alertType"}',
    );

    // Update last alert time
    await prefs.setInt(key, now);
    debugPrint('Sent alert: ${alertData['title']}');
  }

  /// Manually trigger a check (e.g., on app open or pull-to-refresh)
  Future<void> checkNow() async {
    await checkWeatherConditions();
  }
}
