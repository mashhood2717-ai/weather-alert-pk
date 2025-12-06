// lib/services/alert_storage_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_alert.dart';

class AlertStorageService {
  static const String _alertsKey = 'weather_alerts';
  static const String _subscribedCitiesKey = 'subscribed_cities';
  static const int _maxAlerts = 50; // Keep last 50 alerts

  // Singleton pattern
  static final AlertStorageService _instance = AlertStorageService._internal();
  factory AlertStorageService() => _instance;
  AlertStorageService._internal();

  // ==================== ALERTS ====================

  Future<List<WeatherAlert>> getAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? alertsJson = prefs.getString(_alertsKey);

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

    // Add new alert at the beginning
    alerts.insert(0, alert);

    // Keep only last N alerts
    final trimmedAlerts = alerts.take(_maxAlerts).toList();

    final encoded = jsonEncode(trimmedAlerts.map((e) => e.toJson()).toList());
    await prefs.setString(_alertsKey, encoded);
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
    await prefs.setString(_alertsKey, encoded);
  }

  Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();

    final updatedAlerts =
        alerts.map((alert) => alert.copyWith(isRead: true)).toList();

    final encoded = jsonEncode(updatedAlerts.map((e) => e.toJson()).toList());
    await prefs.setString(_alertsKey, encoded);
  }

  Future<void> deleteAlert(String alertId) async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();

    alerts.removeWhere((alert) => alert.id == alertId);

    final encoded = jsonEncode(alerts.map((e) => e.toJson()).toList());
    await prefs.setString(_alertsKey, encoded);
  }

  Future<void> clearAllAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_alertsKey);
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
