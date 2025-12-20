// lib/services/travel_weather_service.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/motorway_point.dart';
import '../secrets.dart';

/// Simple lat/lng class for route points (renamed to avoid conflict with google_maps_flutter)
class RouteLatLng {
  final double latitude;
  final double longitude;

  const RouteLatLng(this.latitude, this.longitude);
}

/// Represents a navigation step (turn-by-turn instruction)
class NavigationStep {
  final String instruction; // HTML instruction from Google
  final String maneuver; // turn-left, turn-right, straight, etc.
  final int distanceMeters;
  final int durationSeconds;
  final RouteLatLng startLocation;
  final RouteLatLng endLocation;
  final String? roadName;

  NavigationStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.startLocation,
    required this.endLocation,
    this.roadName,
  });

  /// Clean instruction (remove HTML tags)
  String get cleanInstruction {
    return instruction
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  /// Get icon for maneuver
  String get maneuverIcon {
    if (maneuver.contains('left')) return '↰';
    if (maneuver.contains('right')) return '↱';
    if (maneuver.contains('uturn')) return '↩';
    if (maneuver.contains('merge')) return '⤵';
    if (maneuver.contains('ramp')) return '⤴';
    if (maneuver.contains('fork')) return '⤳';
    if (maneuver.contains('roundabout')) return '↻';
    return '↑'; // straight
  }
}

/// Represents a route with polyline points and metadata
class RouteData {
  final List<RouteLatLng> polylinePoints;
  final int distanceMeters;
  final int durationSeconds;
  final String? polylineEncoded;
  final List<NavigationStep> steps; // Turn-by-turn navigation steps

  RouteData({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    this.polylineEncoded,
    this.steps = const [],
  });
}

/// Simple cache wrapper for weather data
class _CachedWeather {
  final TravelWeather weather;
  final DateTime fetchedAt;
  _CachedWeather(this.weather) : fetchedAt = DateTime.now();

  bool get isValid => DateTime.now().difference(fetchedAt).inMinutes < 10;
}

/// Service to fetch travel route data, weather, and ETAs
class TravelWeatherService {
  static TravelWeatherService? _instance;
  static TravelWeatherService get instance =>
      _instance ??= TravelWeatherService._();
  TravelWeatherService._();

  // In-memory weather cache with timestamp (cache for 10 minutes)
  static final Map<String, _CachedWeather> _weatherCache = {};

  /// Clear the weather cache (call when loading a new route)
  void clearWeatherCache() {
    _weatherCache.clear();
    debugPrint('🗑️ Weather cache cleared');
  }

  // Cloudflare Worker URL for Pakistan METAR
  static const String _workerUrl =
      'https://travel-weather-api.mashhood2717.workers.dev';

  // Worker is deployed and ready
  static const bool _useWorker = true;

  /// Fetch weather + METAR from Cloudflare Worker (single request)
  /// Returns a map with 'weather' and 'metar' data
  Future<Map<String, dynamic>> fetchTravelDataFromWorker({
    required List<MotorwayPoint> points,
    required List<String> icaoCodes,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_workerUrl/travel-weather'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'points': points
                  .map((p) => {
                        'id': p.id,
                        'lat': p.lat,
                        'lon': p.lon,
                      })
                  .toList(),
              'icao_codes': icaoCodes,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Worker error: ${response.statusCode}');
    } catch (e) {
      debugPrint('Worker fetch failed: $e');
      rethrow;
    }
  }

  /// Convert worker weather response to TravelWeather objects
  List<TravelWeather> parseWorkerWeather(
    Map<String, dynamic> weatherMap,
    List<MotorwayPoint> points,
  ) {
    return points.map((point) {
      final data = weatherMap[point.id] as Map<String, dynamic>?;
      if (data == null || data['error'] != null) {
        return TravelWeather(
          tempC: 0,
          condition: 'Unknown',
          icon: '',
          humidity: 0,
          windKph: 0,
          isDay: true,
        );
      }
      // Default to day if is_day not present
      final isDayValue = data['is_day'];
      final isDay =
          isDayValue == null ? true : (isDayValue == 1 || isDayValue == true);
      return TravelWeather(
        tempC: (data['temp_c'] as num?)?.toDouble() ?? 0,
        condition: data['condition'] as String? ?? 'Unknown',
        icon: data['icon'] as String? ?? '',
        humidity: (data['humidity'] as num?)?.toInt() ?? 0,
        windKph: (data['wind_kph'] as num?)?.toDouble() ?? 0,
        rainChance: null, // WeatherAPI doesn't include in current
        isDay: isDay,
      );
    }).toList();
  }

  /// Check if worker is enabled and configured
  bool get isWorkerEnabled =>
      _useWorker && !_workerUrl.contains('YOUR_SUBDOMAIN');

  /// Get full route with road-level polyline from Google Directions API
  Future<RouteData?> getRoutePolyline({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    List<MotorwayPoint>? waypoints,
  }) async {
    try {
      // For long routes with many waypoints, we need to split into multiple API calls
      // Google API limit is 25 waypoints max (23 intermediate + origin + destination)
      // But for reliability, we'll use 10 waypoints per call

      if (waypoints != null && waypoints.length > 12) {
        // Long route - split into multiple segments
        return await _getRoutePolylineMultiSegment(
          startLat: startLat,
          startLon: startLon,
          endLat: endLat,
          endLon: endLon,
          waypoints: waypoints,
        );
      }

      // Short route - single API call
      String waypointsStr = '';
      if (waypoints != null && waypoints.length > 2) {
        // Only include intermediate points (not start/end)
        final intermediatePoints = waypoints.sublist(1, waypoints.length - 1);
        if (intermediatePoints.isNotEmpty) {
          waypointsStr = '&waypoints=optimize:false|' +
              intermediatePoints.map((p) => '${p.lat},${p.lon}').join('|');
        }
      }

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$startLat,$startLon'
        '&destination=$endLat,$endLon'
        '&mode=driving'
        '$waypointsStr'
        '&key=$googleMapsApiKey',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];

          // Get the overview polyline for backup
          final overviewPolyline =
              route['overview_polyline']['points'] as String;

          // Calculate total distance and duration from all legs
          int totalDistance = 0;
          int totalDuration = 0;

          // Extract turn-by-turn navigation steps AND detailed polyline points
          final List<NavigationStep> steps = [];
          final List<RouteLatLng> detailedPoints = [];

          for (final leg in route['legs']) {
            totalDistance += (leg['distance']['value'] as int);
            totalDuration += (leg['duration']['value'] as int);

            // Extract steps from each leg - use step polylines for accuracy
            for (final step in leg['steps']) {
              steps.add(NavigationStep(
                instruction: step['html_instructions'] ?? '',
                maneuver: step['maneuver'] ?? 'straight',
                distanceMeters: step['distance']['value'] ?? 0,
                durationSeconds: step['duration']['value'] ?? 0,
                startLocation: RouteLatLng(
                  step['start_location']['lat'],
                  step['start_location']['lng'],
                ),
                endLocation: RouteLatLng(
                  step['end_location']['lat'],
                  step['end_location']['lng'],
                ),
              ));

              // IMPORTANT: Decode each step's polyline for precise road alignment
              // This gives us much more detailed points than overview_polyline
              if (step['polyline'] != null &&
                  step['polyline']['points'] != null) {
                final stepPolyline = step['polyline']['points'] as String;
                final stepPoints = _decodePolyline(stepPolyline);

                // Add points, avoiding duplicates at step boundaries
                for (final pt in stepPoints) {
                  if (detailedPoints.isEmpty ||
                      (detailedPoints.last.latitude != pt.latitude ||
                          detailedPoints.last.longitude != pt.longitude)) {
                    detailedPoints.add(pt);
                  }
                }
              }
            }
          }

          // Use detailed points if available, otherwise fall back to overview
          final finalPoints = detailedPoints.isNotEmpty
              ? detailedPoints
              : _decodePolyline(overviewPolyline);

          print(
              '🛣️ Route polyline: ${finalPoints.length} points (detailed from ${steps.length} steps)');

          return RouteData(
            polylinePoints: finalPoints,
            distanceMeters: totalDistance,
            durationSeconds: totalDuration,
            polylineEncoded: overviewPolyline,
            steps: steps,
          );
        }
      }
    } catch (e) {
      print('Error fetching route polyline: $e');
    }
    return null;
  }

  /// Handle long routes by splitting into multiple API calls
  Future<RouteData?> _getRoutePolylineMultiSegment({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    required List<MotorwayPoint> waypoints,
  }) async {
    try {
      // Split waypoints into chunks of 10 (to stay within API limits)
      const int chunkSize = 10;
      final List<RouteLatLng> allPoints = [];
      final List<NavigationStep> allSteps = [];
      int totalDistance = 0;
      int totalDuration = 0;
      String combinedPolyline = '';

      // Create segments
      for (int i = 0; i < waypoints.length - 1; i += chunkSize - 1) {
        final endIndex = (i + chunkSize).clamp(0, waypoints.length);
        final segmentPoints = waypoints.sublist(i, endIndex);

        if (segmentPoints.length < 2) continue;

        final segmentStart = segmentPoints.first;
        final segmentEnd = segmentPoints.last;

        // Build waypoints for this segment (intermediate only)
        String waypointsStr = '';
        if (segmentPoints.length > 2) {
          final intermediatePoints =
              segmentPoints.sublist(1, segmentPoints.length - 1);
          waypointsStr = '&waypoints=optimize:false|' +
              intermediatePoints.map((p) => '${p.lat},${p.lon}').join('|');
        }

        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=${segmentStart.lat},${segmentStart.lon}'
          '&destination=${segmentEnd.lat},${segmentEnd.lon}'
          '&mode=driving'
          '$waypointsStr'
          '&key=$googleMapsApiKey',
        );

        print(
            '📍 Segment ${(i ~/ (chunkSize - 1)) + 1}: ${segmentPoints.length} points');

        final response =
            await http.get(url).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
            final route = data['routes'][0];

            // Get overview polyline for backup
            final polyline = route['overview_polyline']['points'] as String;
            combinedPolyline += polyline;

            // Extract distance, duration, steps AND detailed polyline from each step
            for (final leg in route['legs']) {
              totalDistance += (leg['distance']['value'] as int);
              totalDuration += (leg['duration']['value'] as int);

              for (final step in leg['steps']) {
                allSteps.add(NavigationStep(
                  instruction: step['html_instructions'] ?? '',
                  maneuver: step['maneuver'] ?? 'straight',
                  distanceMeters: step['distance']['value'] ?? 0,
                  durationSeconds: step['duration']['value'] ?? 0,
                  startLocation: RouteLatLng(
                    step['start_location']['lat'],
                    step['start_location']['lng'],
                  ),
                  endLocation: RouteLatLng(
                    step['end_location']['lat'],
                    step['end_location']['lng'],
                  ),
                ));

                // IMPORTANT: Use step-level polylines for precise road alignment
                if (step['polyline'] != null &&
                    step['polyline']['points'] != null) {
                  final stepPolyline = step['polyline']['points'] as String;
                  final stepPoints = _decodePolyline(stepPolyline);

                  // Avoid duplicate points at step boundaries
                  for (final pt in stepPoints) {
                    if (allPoints.isEmpty ||
                        (allPoints.last.latitude != pt.latitude ||
                            allPoints.last.longitude != pt.longitude)) {
                      allPoints.add(pt);
                    }
                  }
                }
              }
            }
          }
        }
      }

      if (allPoints.isNotEmpty) {
        print(
            '✅ Combined route: ${allPoints.length} points from multiple segments');
        return RouteData(
          polylinePoints: allPoints,
          distanceMeters: totalDistance,
          durationSeconds: totalDuration,
          polylineEncoded: combinedPolyline,
          steps: allSteps,
        );
      }
    } catch (e) {
      print('Error fetching multi-segment route: $e');
    }
    return null;
  }

  /// Decode Google's encoded polyline format to list of coordinates
  /// Algorithm: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  List<RouteLatLng> _decodePolyline(String encoded) {
    final List<RouteLatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      // Decode latitude
      int shift = 0;
      int result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      // Decode longitude
      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(RouteLatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  /// Get route ETAs from Google Directions API
  Future<List<Duration>> getRouteETAs({
    required double startLat,
    required double startLon,
    required List<MotorwayPoint> waypoints,
  }) async {
    if (waypoints.isEmpty) return [];

    final List<Duration> etas = [];
    Duration cumulativeTime = Duration.zero;

    // Calculate ETA for each segment
    double currentLat = startLat;
    double currentLon = startLon;

    for (final point in waypoints) {
      try {
        final duration = await _getSegmentDuration(
          currentLat,
          currentLon,
          point.lat,
          point.lon,
        );
        cumulativeTime += duration;
        etas.add(cumulativeTime);
        currentLat = point.lat;
        currentLon = point.lon;
      } catch (e) {
        // Estimate based on distance (assume 100 km/h average on motorway)
        final distance = _calculateDistance(
          currentLat,
          currentLon,
          point.lat,
          point.lon,
        );
        final estimatedMinutes = (distance / 100 * 60).round();
        cumulativeTime += Duration(minutes: estimatedMinutes);
        etas.add(cumulativeTime);
        currentLat = point.lat;
        currentLon = point.lon;
      }
    }

    return etas;
  }

  /// Get driving duration between two points using Google Directions API
  Future<Duration> _getSegmentDuration(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  ) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$fromLat,$fromLon'
      '&destination=$toLat,$toLon'
      '&mode=driving'
      '&key=$googleMapsApiKey',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
        final durationSeconds =
            data['routes'][0]['legs'][0]['duration']['value'] as int;
        return Duration(seconds: durationSeconds);
      }
    }

    throw Exception('Failed to get directions');
  }

  /// Batch fetch weather for multiple points using Cloudflare Worker
  /// This is much faster as it fetches all points in a single request
  Future<List<TravelWeather>> getWeatherForPoints(
    List<MotorwayPoint> points,
  ) async {
    // Check cache first for all points
    final results = <int, TravelWeather>{};
    final pointsToFetch = <int, MotorwayPoint>{};

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final cacheKey =
          '${point.lat.toStringAsFixed(2)}_${point.lon.toStringAsFixed(2)}';

      final cached = _weatherCache[cacheKey];
      if (cached != null && cached.isValid) {
        results[i] = cached.weather;
        debugPrint('📋 Weather cache HIT: ${point.name}');
      } else {
        pointsToFetch[i] = point;
      }
    }

    debugPrint(
        '🌤️ Weather: ${results.length} cached, ${pointsToFetch.length} to fetch');

    if (pointsToFetch.isEmpty) {
      return List.generate(points.length, (i) => results[i]!);
    }

    // Batch fetch from Cloudflare Worker
    try {
      final requestPoints = pointsToFetch.entries
          .map((e) => {
                'id': e.value
                    .id, // Use actual point ID (m2_17, etc.) for worker cache lookup
                'idx': e.key.toString(), // Also send index for response mapping
                'lat': e.value.lat,
                'lon': e.value.lon,
                'name': e.value.name,
              })
          .toList();

      debugPrint('🚀 Fetching ${requestPoints.length} points from worker...');

      final response = await http
          .post(
            Uri.parse('$travelWeatherWorkerUrl/travel-weather'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'points': requestPoints}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final weatherData = data['weather'] as Map<String, dynamic>? ?? {};

        for (final entry in weatherData.entries) {
          // Look up by point ID to find the index
          final pointId = entry.key;
          int? idx;
          for (final e in pointsToFetch.entries) {
            if (e.value.id == pointId) {
              idx = e.key;
              break;
            }
          }
          if (idx != null) {
            final w = entry.value as Map<String, dynamic>;
            final source = w['source']?.toString() ?? 'weatherapi';
            // Default to day if is_day not present (METAR doesn't include it)
            final isDayValue = w['is_day'];
            final isDay = isDayValue == null
                ? true
                : (isDayValue == 1 || isDayValue == true);
            final weather = TravelWeather(
              tempC: (w['temp_c'] as num?)?.toDouble() ?? 0,
              condition: w['condition']?.toString() ?? 'Unknown',
              icon: w['icon']?.toString() ?? '',
              humidity: (w['humidity'] as num?)?.toInt() ?? 0,
              windKph: (w['wind_kph'] as num?)?.toDouble() ?? 0,
              rainChance: null, // Worker doesn't provide this yet
              isDay: isDay,
            );
            results[idx] = weather;

            // Cache the result
            final point = pointsToFetch[idx]!;
            final cacheKey =
                '${point.lat.toStringAsFixed(2)}_${point.lon.toStringAsFixed(2)}';
            _weatherCache[cacheKey] = _CachedWeather(weather);

            // Log with source indicator
            if (source == 'metar') {
              debugPrint(
                  '✅ METAR: ${point.name} = ${weather.tempC}°C (${w['airport_name']})');
            } else {
              debugPrint('✅ WeatherAPI: ${point.name} = ${weather.tempC}°C');
            }
          }
        }

        debugPrint('✅ Worker batch complete: ${weatherData.length} points');
      } else {
        debugPrint('❌ Worker error: ${response.statusCode}');
        // Fall back to individual fetches
        await _fetchWeatherIndividually(pointsToFetch, results);
      }
    } catch (e) {
      debugPrint('❌ Worker batch failed: $e');
      // Fall back to individual fetches using WeatherAPI directly
      await _fetchWeatherIndividually(pointsToFetch, results);
    }

    // Fill any missing with default
    for (int i = 0; i < points.length; i++) {
      results.putIfAbsent(
          i,
          () => TravelWeather(
                tempC: 0,
                condition: 'Unknown',
                icon: '',
                humidity: 0,
                windKph: 0,
                isDay: true,
              ));
    }

    return List.generate(points.length, (i) => results[i]!);
  }

  /// Fallback: fetch weather individually using WeatherAPI
  Future<void> _fetchWeatherIndividually(
    Map<int, MotorwayPoint> pointsToFetch,
    Map<int, TravelWeather> results,
  ) async {
    debugPrint('⚠️ Falling back to individual WeatherAPI fetches...');

    final entries = pointsToFetch.entries.toList();
    for (int i = 0; i < entries.length; i += 5) {
      final batch = entries.skip(i).take(5).toList();

      final futures = batch.map((entry) async {
        try {
          final weather = await _fetchWeatherFromWeatherAPI(
            entry.value.lat,
            entry.value.lon,
          );
          final cacheKey =
              '${entry.value.lat.toStringAsFixed(2)}_${entry.value.lon.toStringAsFixed(2)}';
          _weatherCache[cacheKey] = _CachedWeather(weather);
          debugPrint('✅ WeatherAPI: ${entry.value.name} = ${weather.tempC}°C');
          return MapEntry(entry.key, weather);
        } catch (e) {
          debugPrint('❌ WeatherAPI FAILED for ${entry.value.name}: $e');
          return MapEntry(
            entry.key,
            TravelWeather(
              tempC: 0,
              condition: 'Unknown',
              icon: '',
              humidity: 0,
              windKph: 0,
              isDay: true,
            ),
          );
        }
      }).toList();

      final fetched = await Future.wait(futures);
      for (final entry in fetched) {
        results[entry.key] = entry.value;
      }

      if (i + 5 < entries.length) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Fetch weather from WeatherAPI.com directly (fallback)
  Future<TravelWeather> _fetchWeatherFromWeatherAPI(
      double lat, double lon) async {
    final url = Uri.parse(
      'https://api.weatherapi.com/v1/current.json?key=$weatherApiKey&q=$lat,$lon&aqi=no',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('WeatherAPI error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final current = data['current'];

    // Default to day if is_day not present
    final isDayValue = current['is_day'];
    final isDay =
        isDayValue == null ? true : (isDayValue == 1 || isDayValue == true);
    return TravelWeather(
      tempC: (current['temp_c'] as num?)?.toDouble() ?? 0,
      condition: current['condition']?['text']?.toString() ?? 'Unknown',
      icon: current['condition']?['icon']?.toString() ?? '',
      humidity: (current['humidity'] as num?)?.toInt() ?? 0,
      windKph: (current['wind_kph'] as num?)?.toDouble() ?? 0,
      rainChance: null,
      isDay: isDay,
    );
  }

  /// Calculate prayer times for a specific point and arrival time
  Future<Map<String, String>> getPrayerTimesForPoint(
    double lat,
    double lon,
    DateTime arrivalTime,
  ) async {
    // Use Aladhan API for prayer times
    final dateStr =
        '${arrivalTime.day}-${arrivalTime.month}-${arrivalTime.year}';
    final url = Uri.parse(
      'https://api.aladhan.com/v1/timings/$dateStr'
      '?latitude=$lat&longitude=$lon&method=1', // University of Islamic Sciences, Karachi
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final timings = data['data']['timings'] as Map<String, dynamic>;
        return {
          'Fajr': _formatPrayerTime(timings['Fajr']),
          'Dhuhr': _formatPrayerTime(timings['Dhuhr']),
          'Asr': _formatPrayerTime(timings['Asr']),
          'Maghrib': _formatPrayerTime(timings['Maghrib']),
          'Isha': _formatPrayerTime(timings['Isha']),
        };
      }
    } catch (e) {
      // Return empty on error
    }
    return {};
  }

  /// Get next prayer at arrival time
  String? getNextPrayer(Map<String, String> prayerTimes, DateTime arrivalTime) {
    final prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final arrivalMinutes = arrivalTime.hour * 60 + arrivalTime.minute;

    for (final prayer in prayers) {
      final timeStr = prayerTimes[prayer];
      if (timeStr != null) {
        final parts = timeStr.split(':');
        if (parts.length == 2) {
          final prayerMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
          if (prayerMinutes > arrivalMinutes) {
            return prayer;
          }
        }
      }
    }
    return 'Fajr'; // Next day
  }

  String _formatPrayerTime(String? time) {
    if (time == null) return '--:--';
    // Remove timezone info like "(PKT)"
    return time.split(' ').first;
  }

  /// Calculate distance between two coordinates (Haversine)
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
}
