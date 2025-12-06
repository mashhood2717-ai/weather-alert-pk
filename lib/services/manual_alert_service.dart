// lib/services/manual_alert_service.dart
// Handles manual alerts from admin portal with location-based targeting

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_alert.dart';
import 'alert_storage_service.dart';
import 'notification_service.dart';

class ManualAlertService {
  static final ManualAlertService _instance = ManualAlertService._internal();
  factory ManualAlertService() => _instance;
  ManualAlertService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  final AlertStorageService _alertStorage = AlertStorageService();

  StreamSubscription? _alertSubscription;
  Position? _lastKnownPosition;
  String? _deviceId;

  /// Initialize manual alert listening
  Future<void> initialize() async {
    try {
      print('ManualAlertService: Starting initialization...');
      await _getDeviceId();
      print('ManualAlertService: Device ID = $_deviceId');

      // Don't await location - do it in background
      _updateUserLocation().catchError((e) {
        print('ManualAlertService: Location update error: $e');
      });

      _listenForManualAlerts();
      print('ManualAlertService initialized successfully');
    } catch (e) {
      print('ManualAlertService: Initialization error: $e');
    }
  }

  /// Generate/get unique device ID
  Future<void> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null) {
      _deviceId =
          'device_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(8)}';
      await prefs.setString('device_id', _deviceId!);
    }
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Update user's location in Firestore for targeting
  Future<void> _updateUserLocation() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        print(
            'Location permission denied - using subscribed cities for alerts');
        return;
      }

      // Get current position
      _lastKnownPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      // Get subscribed cities
      final prefs = await SharedPreferences.getInstance();
      final subscribedCities = prefs.getStringList('subscribed_cities') ?? [];

      // Store in Firestore
      if (_deviceId != null && _lastKnownPosition != null) {
        await _firestore.collection('user_locations').doc(_deviceId).set({
          'lat': _lastKnownPosition!.latitude,
          'lng': _lastKnownPosition!.longitude,
          'subscribedCities': subscribedCities,
          'lastUpdated': FieldValue.serverTimestamp(),
          'platform': 'android',
        }, SetOptions(merge: true));

        print(
            'User location updated: ${_lastKnownPosition!.latitude}, ${_lastKnownPosition!.longitude}');
      }
    } catch (e) {
      print('Error updating user location: $e');
    }
  }

  /// Listen for new manual alerts
  void _listenForManualAlerts() {
    print('Setting up manual alerts listener...');

    _alertSubscription = _firestore
        .collection('manual_alerts')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
      print('Firestore snapshot received: ${snapshot.docs.length} documents');
      for (var change in snapshot.docChanges) {
        print('Document change: ${change.type} - ${change.doc.id}');
        if (change.type == DocumentChangeType.added) {
          _processNewAlert(change.doc);
        }
      }
    }, onError: (e) {
      print('Error listening for manual alerts: $e');
    });

    print('Listening for manual alerts...');
  }

  /// Process a new alert and check if user should receive it
  Future<void> _processNewAlert(DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) {
        print('Alert data is null');
        return;
      }

      final alertId = doc.id;
      print('Processing alert: $alertId');
      print('Alert data: $data');

      // Check if already processed
      final prefs = await SharedPreferences.getInstance();
      final processedAlerts =
          prefs.getStringList('processed_manual_alerts') ?? [];
      if (processedAlerts.contains(alertId)) {
        print('Alert already processed: $alertId');
        return; // Already shown this alert
      }

      // Get alert location
      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) {
        print('Alert has no location data');
        return;
      }

      final alertLat = (location['lat'] as num?)?.toDouble();
      final alertLng = (location['lng'] as num?)?.toDouble();
      final radiusKm = (location['radius'] as num?)?.toDouble() ?? 25.0;
      final cityName = location['city'] as String? ?? 'Unknown';

      print(
          'Alert location: $cityName ($alertLat, $alertLng) radius: ${radiusKm}km');

      // Check if user is within radius
      bool shouldReceive = false;
      String matchReason = '';

      // Method 1: Check by GPS location
      if (_lastKnownPosition != null && alertLat != null && alertLng != null) {
        final distance = _calculateDistance(
          _lastKnownPosition!.latitude,
          _lastKnownPosition!.longitude,
          alertLat,
          alertLng,
        );
        print('User distance from alert: ${distance.toStringAsFixed(1)}km');

        if (distance <= radiusKm) {
          shouldReceive = true;
          matchReason =
              'You are within ${distance.toStringAsFixed(1)}km of the alert area';
        }
      } else {
        print('No GPS position available for distance check');
      }

      // Method 2: Check by subscribed cities
      if (!shouldReceive) {
        final subscribedCities = prefs.getStringList('subscribed_cities') ?? [];
        print('User subscribed cities: $subscribedCities');
        final alertCity = cityName.toLowerCase();

        for (final city in subscribedCities) {
          if (alertCity.contains(city.toLowerCase()) ||
              city.toLowerCase().contains(alertCity)) {
            shouldReceive = true;
            matchReason = 'Alert for your subscribed city: $cityName';
            print('City match found: $city matches $alertCity');
            break;
          }
        }
      }

      if (!shouldReceive) {
        print('Alert not relevant for user: $cityName (radius: ${radiusKm}km)');
        return;
      }

      print('✅ User should receive this alert! Reason: $matchReason');

      // Mark as processed
      processedAlerts.add(alertId);
      // Keep only last 100 processed alerts
      if (processedAlerts.length > 100) {
        processedAlerts.removeAt(0);
      }
      await prefs.setStringList('processed_manual_alerts', processedAlerts);

      // Create and show alert
      final alert = WeatherAlert(
        id: alertId,
        title: data['title'] ?? 'Weather Alert',
        body: data['message'] ?? '',
        city: cityName,
        severity: data['severity'] ?? 'medium',
        receivedAt: DateTime.now(),
        data: {
          'type': data['type'] ?? 'other',
          'radius': radiusKm.toString(),
          'match_reason': matchReason,
          'source': 'admin_portal',
        },
      );

      // Save to storage
      await _alertStorage.saveAlert(alert);

      // Show notification
      await _notificationService.showWeatherAlert(
        title: '${_getAlertEmoji(data['type'])} ${alert.title}',
        body: '📍 $cityName\n${alert.body}',
        severity: alert.severity ?? 'medium',
      );

      print('Manual alert shown: ${alert.title} for $cityName');
    } catch (e) {
      print('Error processing manual alert: $e');
    }
  }

  /// Calculate distance between two points using Haversine formula
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  String _getAlertEmoji(String? type) {
    switch (type) {
      case 'rain':
        return '🌧️';
      case 'heat':
        return '🌡️';
      case 'cold':
        return '❄️';
      case 'storm':
        return '⛈️';
      case 'wind':
        return '💨';
      case 'fog':
        return '🌫️';
      case 'dust':
        return '🌪️';
      case 'snow':
        return '🌨️';
      default:
        return '⚠️';
    }
  }

  /// Refresh user location periodically
  Future<void> refreshLocation() async {
    await _updateUserLocation();
  }

  /// Stop listening
  void dispose() {
    _alertSubscription?.cancel();
  }
}
