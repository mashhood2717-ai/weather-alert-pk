// lib/services/settings_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Temperature unit options
enum TemperatureUnit {
  metric, // Celsius
  imperial, // Fahrenheit
  hybrid, // Celsius with mph wind
}

/// Theme mode options
enum AppThemeMode {
  auto, // Based on sunrise/sunset (default)
  light, // Always light
  dark, // Always dark
  system, // Follow system setting
}

/// Wind speed unit options
enum WindUnit {
  kmh, // Kilometers per hour
  mph, // Miles per hour
  ms, // Meters per second
  knots, // Knots (for aviation)
}

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // Keys for SharedPreferences
  static const String _tempUnitKey = 'temperature_unit';
  static const String _windUnitKey = 'wind_unit';
  static const String _themeModeKey = 'theme_mode';
  static const String _travelingModeKey = 'traveling_mode';

  // Current settings
  TemperatureUnit _temperatureUnit = TemperatureUnit.metric;
  WindUnit _windUnit = WindUnit.kmh;
  AppThemeMode _themeMode = AppThemeMode.auto;
  bool _travelingMode = false;
  bool _isInitialized = false;

  // Getters
  TemperatureUnit get temperatureUnit => _temperatureUnit;
  WindUnit get windUnit => _windUnit;
  AppThemeMode get themeMode => _themeMode;
  bool get travelingMode => _travelingMode;
  bool get isInitialized => _isInitialized;

  /// Initialize settings from SharedPreferences
  Future<void> initialize() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();

    // Load temperature unit
    final tempUnitStr = prefs.getString(_tempUnitKey) ?? 'metric';
    _temperatureUnit = TemperatureUnit.values.firstWhere(
      (e) => e.name == tempUnitStr,
      orElse: () => TemperatureUnit.metric,
    );

    // Load wind unit
    final windUnitStr = prefs.getString(_windUnitKey) ?? 'kmh';
    _windUnit = WindUnit.values.firstWhere(
      (e) => e.name == windUnitStr,
      orElse: () => WindUnit.kmh,
    );

    // Load theme mode
    final themeModeStr = prefs.getString(_themeModeKey) ?? 'auto';
    _themeMode = AppThemeMode.values.firstWhere(
      (e) => e.name == themeModeStr,
      orElse: () => AppThemeMode.auto,
    );

    // Load traveling mode
    _travelingMode = prefs.getBool(_travelingModeKey) ?? false;

    _isInitialized = true;
    notifyListeners();
  }

  /// Set temperature unit
  Future<void> setTemperatureUnit(TemperatureUnit unit) async {
    if (_temperatureUnit == unit) return;
    _temperatureUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tempUnitKey, unit.name);
    notifyListeners();
  }

  /// Set wind unit
  Future<void> setWindUnit(WindUnit unit) async {
    if (_windUnit == unit) return;
    _windUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_windUnitKey, unit.name);
    notifyListeners();
  }

  /// Set theme mode
  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
    notifyListeners();
  }

  /// Set traveling mode
  Future<void> setTravelingMode(bool enabled) async {
    if (_travelingMode == enabled) return;
    _travelingMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_travelingModeKey, enabled);
    notifyListeners();
  }

  // ==================== Unit Conversion Helpers ====================

  /// Convert temperature based on current unit setting
  double convertTemperature(double celsiusValue) {
    switch (_temperatureUnit) {
      case TemperatureUnit.imperial:
        return celsiusValue * 9 / 5 + 32;
      case TemperatureUnit.metric:
      case TemperatureUnit.hybrid:
        return celsiusValue;
    }
  }

  /// Get temperature unit symbol
  String get temperatureSymbol {
    switch (_temperatureUnit) {
      case TemperatureUnit.imperial:
        return '°F';
      case TemperatureUnit.metric:
      case TemperatureUnit.hybrid:
        return '°C';
    }
  }

  /// Convert wind speed based on current unit setting
  double convertWindSpeed(double kmhValue) {
    switch (_windUnit) {
      case WindUnit.kmh:
        return kmhValue;
      case WindUnit.mph:
        return kmhValue * 0.621371;
      case WindUnit.ms:
        return kmhValue / 3.6;
      case WindUnit.knots:
        return kmhValue * 0.539957;
    }
  }

  /// Get wind speed unit symbol
  String get windSymbol {
    switch (_windUnit) {
      case WindUnit.kmh:
        return 'km/h';
      case WindUnit.mph:
        return 'mph';
      case WindUnit.ms:
        return 'm/s';
      case WindUnit.knots:
        return 'kn';
    }
  }

  /// Convert wind for hybrid/imperial mode
  double convertWindSpeedHybrid(double kmhValue) {
    if (_temperatureUnit == TemperatureUnit.hybrid ||
        _temperatureUnit == TemperatureUnit.imperial) {
      return kmhValue * 0.621371; // Convert to mph
    }
    return convertWindSpeed(kmhValue);
  }

  /// Get wind symbol for hybrid/imperial mode
  String get windSymbolHybrid {
    if (_temperatureUnit == TemperatureUnit.hybrid ||
        _temperatureUnit == TemperatureUnit.imperial) {
      return 'mph';
    }
    return windSymbol;
  }

  /// Get display name for temperature unit
  static String getTemperatureUnitName(TemperatureUnit unit) {
    switch (unit) {
      case TemperatureUnit.metric:
        return 'Metric (°C, km/h)';
      case TemperatureUnit.imperial:
        return 'Imperial (°F, mph)';
      case TemperatureUnit.hybrid:
        return 'Hybrid (°C, mph)';
    }
  }

  /// Get display name for theme mode
  static String getThemeModeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.auto:
        return 'Auto (Sunrise/Sunset)';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.system:
        return 'Follow System';
    }
  }

  /// Get display name for wind unit
  static String getWindUnitName(WindUnit unit) {
    switch (unit) {
      case WindUnit.kmh:
        return 'Kilometers/hour (km/h)';
      case WindUnit.mph:
        return 'Miles/hour (mph)';
      case WindUnit.ms:
        return 'Meters/second (m/s)';
      case WindUnit.knots:
        return 'Knots (kn)';
    }
  }
}
