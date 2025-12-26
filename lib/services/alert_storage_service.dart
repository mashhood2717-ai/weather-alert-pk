// lib/services/alert_storage_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/weather_alert.dart';
import 'user_service.dart';

class AlertStorageService {
  static const String _alertsKey = 'weather_alerts';
  static const String _subscribedCitiesKey = 'subscribed_cities';
  static const int _maxAlerts = 50; // Keep last 50 alerts
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Singleton pattern
  static final AlertStorageService _instance = AlertStorageService._internal();
  factory AlertStorageService() => _instance;
  AlertStorageService._internal();

  /// Get the user-specific alerts key
  String get _userAlertsKey {
    final userId = UserService().userId;
    if (userId.isNotEmpty) {
      return '${_alertsKey}_$userId';
    }
    return _alertsKey;
  }

  // ==================== ALERTS ====================

  Future<List<WeatherAlert>> getAlerts() async {
    final prefs = await SharedPreferences.getInstance();

    // Try user-specific key first, fall back to generic key
    String? alertsJson = prefs.getString(_userAlertsKey);

    // If no user-specific alerts, check generic key and migrate
    if (alertsJson == null) {
      alertsJson = prefs.getString(_alertsKey);

      // Migrate existing alerts to user-specific key
      if (alertsJson != null && _userAlertsKey != _alertsKey) {
        await prefs.setString(_userAlertsKey, alertsJson);
        print('📦 Migrated alerts to user-specific storage');
      }
    }

    if (alertsJson == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(alertsJson);
      return decoded.map((e) => WeatherAlert.fromJson(e)).toList();
    } catch (e) {
      print('Error parsing alerts: $e');
      return [];
    }
  }

  Future<void> saveAlert(WeatherAlert alert) async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();

    // Check for duplicates - same id, or same title+city within last hour
    final isDuplicate = alerts.any((existing) {
      // Exact ID match
      if (existing.id == alert.id) return true;

      // Same title, city, and within 1 hour
      if (existing.title == alert.title &&
          existing.city == alert.city &&
          existing.severity == alert.severity) {
        final timeDiff =
            alert.receivedAt.difference(existing.receivedAt).inMinutes.abs();
        if (timeDiff < 60) return true;
      }

      return false;
    });

    if (isDuplicate) {
      print('Alert skipped (duplicate): ${alert.title} - ${alert.city}');
      return;
    }

    // Add new alert at the beginning
    alerts.insert(0, alert);

    // Keep only last N alerts
    final trimmedAlerts = alerts.take(_maxAlerts).toList();

    final encoded = jsonEncode(trimmedAlerts.map((e) => e.toJson()).toList());
    await prefs.setString(_userAlertsKey, encoded);

    // Record alert receipt to Firestore
    await UserService().recordAlertReceived(
      alertId: alert.id,
      alertTitle: alert.title,
      alertType: alert.severity ?? 'unknown',
    );
  }

  Future<void> markAlertAsRead(String alertId) async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();

    final updatedAlerts = alerts.map((alert) {
      if (alert.id == alertId) {
        return alert.copyWith(isRead: true);
      }
      return alert;
    }).toList();

    final encoded = jsonEncode(updatedAlerts.map((e) => e.toJson()).toList());
    await prefs.setString(_userAlertsKey, encoded);
    
    // Sync read status to Firestore for cross-device/reinstall persistence
    await _syncReadAlertToCloud(alertId);
  }
  
  /// Sync a read alert ID to Firestore so it persists across reinstalls
  Future<void> _syncReadAlertToCloud(String alertId) async {
    final userId = UserService().userId;
    if (userId.isEmpty) return;
    
    try {
      await _firestore.collection('users').doc(userId).set({
        'readAlertIds': FieldValue.arrayUnion([alertId]),
        'lastReadSync': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('☁️ Synced read alert to cloud: $alertId');
    } catch (e) {
      print('☁️ Error syncing read alert: $e');
    }
  }
  
  /// Fetch read alert IDs from Firestore and apply to local alerts
  Future<void> syncReadStatusFromCloud() async {
    final userId = UserService().userId;
    if (userId.isEmpty) return;
    
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return;
      
      final data = doc.data();
      final List<dynamic> cloudReadIds = data?['readAlertIds'] ?? [];
      
      if (cloudReadIds.isEmpty) return;
      
      // Apply cloud read status to local alerts
      final prefs = await SharedPreferences.getInstance();
      final alerts = await getAlerts();
      bool hasChanges = false;
      
      final updatedAlerts = alerts.map((alert) {
        if (cloudReadIds.contains(alert.id) && !alert.isRead) {
          hasChanges = true;
          return alert.copyWith(isRead: true);
        }
        return alert;
      }).toList();
      
      if (hasChanges) {
        final encoded = jsonEncode(updatedAlerts.map((e) => e.toJson()).toList());
        await prefs.setString(_userAlertsKey, encoded);
        print('☁️ Applied ${cloudReadIds.length} read alerts from cloud');
      }
    } catch (e) {
      print('☁️ Error fetching read status from cloud: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();

    final updatedAlerts =
        alerts.map((alert) => alert.copyWith(isRead: true)).toList();

    final encoded = jsonEncode(updatedAlerts.map((e) => e.toJson()).toList());
    await prefs.setString(_userAlertsKey, encoded);
  }

  Future<void> deleteAlert(String alertId) async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();

    alerts.removeWhere((alert) => alert.id == alertId);

    final encoded = jsonEncode(alerts.map((e) => e.toJson()).toList());
    await prefs.setString(_userAlertsKey, encoded);
  }

  Future<void> clearAllAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userAlertsKey);
  }

  /// Remove duplicate alerts from storage
  Future<void> removeDuplicates() async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();

    final seen = <String>{};
    final uniqueAlerts = <WeatherAlert>[];

    for (final alert in alerts) {
      // Create a key based on title, city, severity, and hour
      final hourKey =
          '${alert.receivedAt.year}-${alert.receivedAt.month}-${alert.receivedAt.day}-${alert.receivedAt.hour}';
      final key = '${alert.title}_${alert.city}_${alert.severity}_$hourKey';

      if (!seen.contains(key)) {
        seen.add(key);
        uniqueAlerts.add(alert);
      }
    }

    if (uniqueAlerts.length < alerts.length) {
      print('Removed ${alerts.length - uniqueAlerts.length} duplicate alerts');
      final encoded = jsonEncode(uniqueAlerts.map((e) => e.toJson()).toList());
      await prefs.setString(_userAlertsKey, encoded);
    }
  }

  Future<int> getUnreadCount() async {
    final alerts = await getAlerts();
    return alerts.where((a) => !a.isRead).length;
  }

  // ==================== CITY SUBSCRIPTIONS ====================

  Future<List<String>> getSubscribedCities() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_subscribedCitiesKey) ?? [];
  }

  Future<void> subscribeToCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    final cities = await getSubscribedCities();

    if (!cities.contains(city)) {
      cities.add(city);
      await prefs.setStringList(_subscribedCitiesKey, cities);
    }
  }

  Future<void> unsubscribeFromCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    final cities = await getSubscribedCities();

    cities.remove(city);
    await prefs.setStringList(_subscribedCitiesKey, cities);
  }

  Future<bool> isSubscribedToCity(String city) async {
    final cities = await getSubscribedCities();
    return cities.contains(city);
  }
}
