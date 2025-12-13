// lib/services/persistent_notification_service.dart

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage persistent notification in notification bar
/// Shows weather condition, temperature, and next prayer time
class PersistentNotificationService {
  static final PersistentNotificationService _instance =
      PersistentNotificationService._internal();
  factory PersistentNotificationService() => _instance;
  PersistentNotificationService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.mashhood.weatheralert/persistent_notification');

  Timer? _updateTimer;
  Timer? _timeUpdateTimer;
  bool _isRunning = false;

  // Current notification data
  String _condition = '--';
  String _temperature = '--';
  String _nextPrayer = '--';
  String _nextPrayerTime = '--';
  String _city = '--';
  DateTime? _lastUpdated;

  bool get isRunning => _isRunning;

  /// Initialize the service
  Future<void> initialize() async {
    // Set up method channel handler for refresh button
    _channel.setMethodCallHandler(_handleMethodCall);

    // Check if notification was previously enabled
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled =
        prefs.getBool('persistent_notification_enabled') ?? false;

    // Read traveling mode directly from prefs to avoid race condition
    final travelingMode = prefs.getBool('traveling_mode') ?? false;

    if (wasEnabled && travelingMode) {
      await startNotification();
    }
  }

  /// Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onRefreshPressed':
        // Trigger refresh callback
        _onRefreshCallback?.call();
        return true;
      default:
        throw PlatformException(
          code: 'UNSUPPORTED_METHOD',
          message: 'Method ${call.method} not supported',
        );
    }
  }

  // Callback for refresh button
  VoidCallback? _onRefreshCallback;

  /// Set callback for refresh button press
  void setRefreshCallback(VoidCallback callback) {
    _onRefreshCallback = callback;
  }

  /// Start the persistent notification
  Future<bool> startNotification() async {
    try {
      _lastUpdated = DateTime.now();
      final result = await _channel.invokeMethod('startNotification', {
        'condition': _condition,
        'temperature': _temperature,
        'nextPrayer': _nextPrayer,
        'nextPrayerTime': _nextPrayerTime,
        'city': _city,
        'lastUpdated': _getTimeSinceUpdate(),
      });

      _isRunning = result == true;

      // Save state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('persistent_notification_enabled', _isRunning);

      // Start background update timer if traveling mode is on
      if (_isRunning) {
        _startBackgroundUpdates();
      }

      return _isRunning;
    } on PlatformException catch (e) {
      print('Failed to start persistent notification: ${e.message}');
      return false;
    }
  }

  /// Stop the persistent notification
  Future<bool> stopNotification() async {
    try {
      final result = await _channel.invokeMethod('stopNotification');
      _isRunning = !(result == true);

      // Save state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('persistent_notification_enabled', false);

      // Stop background updates
      _stopBackgroundUpdates();

      return !_isRunning;
    } on PlatformException catch (e) {
      print('Failed to stop persistent notification: ${e.message}');
      return false;
    }
  }

  /// Update notification content
  Future<void> updateNotification({
    String? condition,
    String? temperature,
    String? nextPrayer,
    String? nextPrayerTime,
    String? city,
  }) async {
    // Update local values
    if (condition != null) _condition = condition;
    if (temperature != null) _temperature = temperature;
    if (nextPrayer != null) _nextPrayer = nextPrayer;
    if (nextPrayerTime != null) _nextPrayerTime = nextPrayerTime;
    if (city != null) _city = city;

    if (!_isRunning) return;

    _lastUpdated = DateTime.now();

    try {
      await _channel.invokeMethod('updateNotification', {
        'condition': _condition,
        'temperature': _temperature,
        'nextPrayer': _nextPrayer,
        'nextPrayerTime': _nextPrayerTime,
        'city': _city,
        'lastUpdated': _getTimeSinceUpdate(),
      });
    } on PlatformException catch (e) {
      print('Failed to update notification: ${e.message}');
    }
  }

  /// Start periodic background updates when traveling mode is on
  void _startBackgroundUpdates() {
    _stopBackgroundUpdates();

    // Only start background updates when notification is running (traveling mode)
    if (!_isRunning) return;

    // Update time display every 2 minutes (saves battery vs 1 min)
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _updateTimeDisplay();
    });

    // Refresh weather every 30 minutes when traveling (saves battery vs 15 min)
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _onRefreshCallback?.call();
    });
  }

  /// Update just the time display without full refresh
  Future<void> _updateTimeDisplay() async {
    if (!_isRunning) return;
    try {
      await _channel.invokeMethod('updateNotification', {
        'condition': _condition,
        'temperature': _temperature,
        'nextPrayer': _nextPrayer,
        'nextPrayerTime': _nextPrayerTime,
        'city': _city,
        'lastUpdated': _getTimeSinceUpdate(),
      });
    } catch (_) {}
  }

  /// Get human-readable time since last update
  String _getTimeSinceUpdate() {
    if (_lastUpdated == null) return 'now';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours == 1) return '1 hour ago';
    return '${diff.inHours} hours ago';
  }

  /// Stop background updates
  void _stopBackgroundUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = null;
  }

  /// Toggle notification based on traveling mode
  Future<void> syncWithTravelingMode(bool isTraveling) async {
    if (isTraveling && !_isRunning) {
      await startNotification();
    } else if (!isTraveling && _isRunning) {
      await stopNotification();
    } else if (isTraveling && _isRunning) {
      _startBackgroundUpdates();
    }
  }

  /// Dispose resources
  void dispose() {
    _stopBackgroundUpdates();
  }
}
