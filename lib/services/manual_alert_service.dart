// lib/services/manual_alert_service.dart
// Handles manual alerts from admin portal with location-based targeting

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_alert.dart';
import 'alert_storage_service.dart';
import 'favorites_service.dart';
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
      await _getDeviceId();

      // Don't await location - do it in background
      _updateUserLocation().catchError((_) {});

      _listenForManualAlerts();
    } catch (_) {
      // Initialization error handled silently
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
      }
    } catch (e) {
      // Silently handle location update errors
    }
  }

  /// Listen for new manual alerts
  void _listenForManualAlerts() {
    _alertSubscription = _firestore
        .collection('manual_alerts')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _processNewAlert(change.doc);
        }
      }
    });
  }

  /// Process a new alert and check if user should receive it
  Future<void> _processNewAlert(DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return;

      final alertId = doc.id;

      // Check if already processed
      final prefs = await SharedPreferences.getInstance();
      final processedAlerts =
          prefs.getStringList('processed_manual_alerts') ?? [];
      if (processedAlerts.contains(alertId)) {
        return; // Already shown this alert
      }

      // Get alert location
      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) return;

      final alertLat = (location['lat'] as num?)?.toDouble();
      final alertLng = (location['lng'] as num?)?.toDouble();
      final radiusKm = (location['radius'] as num?)?.toDouble() ?? 25.0;
      final cityName = location['city'] as String? ?? 'Unknown';
      final mode = location['mode'] as String? ?? 'radius';
      final polygon = location['polygon'] as List<dynamic>?;

      // Ensure we have fresh location for checking
      if (_lastKnownPosition == null) {
        try {
          _lastKnownPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
          );
        } catch (e) {
          // GPS not available
        }
      }

      // Check if user is within target area
      bool shouldReceive = false;
      String matchReason = '';

      // Method 1: Check by GPS location
      if (_lastKnownPosition != null) {
        final userLat = _lastKnownPosition!.latitude;
        final userLng = _lastKnownPosition!.longitude;

        if (mode == 'polygon' && polygon != null && polygon.length >= 3) {
          if (_isPointInPolygon(userLat, userLng, polygon)) {
            shouldReceive = true;
            matchReason = 'You are inside the alert zone';
          }
        } else if (alertLat != null && alertLng != null) {
          final distance =
              _calculateDistance(userLat, userLng, alertLat, alertLng);
          if (distance <= radiusKm) {
            shouldReceive = true;
            matchReason =
                'You are within ${distance.toStringAsFixed(1)}km of the alert area';
          }
        }
      }

      // Method 2: Check by subscribed cities
      if (!shouldReceive) {
        final subscribedCities = prefs.getStringList('subscribed_cities') ?? [];
        final alertCity = cityName.toLowerCase();

        for (final city in subscribedCities) {
          if (alertCity.contains(city.toLowerCase()) ||
              city.toLowerCase().contains(alertCity)) {
            shouldReceive = true;
            matchReason = 'Alert for your subscribed city: $cityName';
            break;
          }
        }
      }

      // Method 3: Check by favorite locations
      if (!shouldReceive) {
        final favorites = await _getFavoriteLocations(prefs);

        for (final fav in favorites) {
          if (mode == 'polygon' && polygon != null && polygon.length >= 3) {
            if (_isPointInPolygon(fav.lat, fav.lon, polygon)) {
              matchReason = 'Alert affects your favorite location: ${fav.name}';
              break;
            }
          } else if (alertLat != null && alertLng != null) {
            final distance =
                _calculateDistance(fav.lat, fav.lon, alertLat, alertLng);
            if (distance <= radiusKm) {
              shouldReceive = true;
              matchReason = 'Alert affects your favorite location: ${fav.name}';
              break;
            }
          }
        }
      }

      if (!shouldReceive) return;

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
          'mode': mode,
          'zone_name': location['zoneName'] ?? cityName,
          'match_reason': matchReason,
          'source': 'admin_portal',
        },
      );

      // Save to storage (for alerts history)
      await _alertStorage.saveAlert(alert);

      // Show local notification since Cloud Functions may not be deployed
      // This ensures user gets notified when app detects they're in alert zone
      await _notificationService.showWeatherAlert(
        title: alert.title,
        body: '${alert.city}: ${alert.body}',
        payload: jsonEncode({
          'type': 'manual_alert',
          'alert_id': alertId,
          'city': cityName,
        }),
      );
    } catch (e) {
      // Error processing alert
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

  /// Check if a point is inside a polygon using ray casting algorithm
  bool _isPointInPolygon(double lat, double lng, List<dynamic> polygon) {
    if (polygon.length < 3) return false;

    bool inside = false;
    final n = polygon.length;

    for (int i = 0, j = n - 1; i < n; j = i++) {
      final pi = polygon[i] as Map<String, dynamic>;
      final pj = polygon[j] as Map<String, dynamic>;

      final xi = (pi['lat'] as num?)?.toDouble() ?? 0;
      final yi = (pi['lng'] as num?)?.toDouble() ?? 0;
      final xj = (pj['lat'] as num?)?.toDouble() ?? 0;
      final yj = (pj['lng'] as num?)?.toDouble() ?? 0;

      final intersect = (yi > lng) != (yj > lng) &&
          lat < (xj - xi) * (lng - yi) / (yj - yi) + xi;

      if (intersect) inside = !inside;
    }

    return inside;
  }

  /// Get favorite locations from SharedPreferences
  Future<List<FavoriteLocation>> _getFavoriteLocations(
      SharedPreferences prefs) async {
    try {
      final String? favoritesJson = prefs.getString('favorite_locations');
      if (favoritesJson == null) return [];

      final List<dynamic> decoded = jsonDecode(favoritesJson);
      return decoded.map((json) => FavoriteLocation.fromJson(json)).toList();
    } catch (e) {
      return [];
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
