// lib/services/widget_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to update the Android home screen widget
class WidgetService {
  static final WidgetService _instance = WidgetService._internal();
  factory WidgetService() => _instance;
  WidgetService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.mashhood.weatheralert/widget');

  // Callback for widget refresh button
  VoidCallback? _onRefreshCallback;

  /// Initialize the service
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onWidgetRefresh':
        _onRefreshCallback?.call();
        return true;
      default:
        throw PlatformException(
          code: 'UNSUPPORTED_METHOD',
          message: 'Method ${call.method} not supported',
        );
    }
  }

  /// Set callback for widget refresh button press
  void setRefreshCallback(VoidCallback callback) {
    _onRefreshCallback = callback;
  }

  /// Update the home screen widget with weather and prayer data
  Future<void> updateWidget({
    required String city,
    required String temp,
    required String condition,
    required String feelsLike,
    required String humidity,
    required String wind,
    required String uv,
    required bool isDay,
    required String nextPrayer,
    required String nextPrayerTime,
    required String fajr,
    required String dhuhr,
    required String asr,
    required String maghrib,
    required String isha,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'city': city,
        'temp': temp,
        'condition': condition,
        'feelsLike': feelsLike,
        'humidity': humidity,
        'wind': wind,
        'uv': uv,
        'isDay': isDay,
        'nextPrayer': nextPrayer,
        'nextPrayerTime': nextPrayerTime,
        'fajr': fajr,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to update widget: ${e.message}');
    }
  }
}

