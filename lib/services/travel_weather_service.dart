// lib/services/travel_weather_service.dart

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/motorway_point.dart';
import '../secrets.dart';
import 'open_meteo_service.dart';

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

/// Service to fetch travel route data, weather, and ETAs
class TravelWeatherService {
  static TravelWeatherService? _instance;
  static TravelWeatherService get instance =>
      _instance ??= TravelWeatherService._();
  TravelWeatherService._();

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

          print('🛣️ Route polyline: ${finalPoints.length} points (detailed from ${steps.length} steps)');

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

  /// Batch fetch weather for multiple points
  Future<List<TravelWeather>> getWeatherForPoints(
    List<MotorwayPoint> points,
  ) async {
    final List<TravelWeather> weatherList = [];

    for (final point in points) {
      try {
        final weather = await _fetchWeatherForPoint(point.lat, point.lon);
        weatherList.add(weather);
      } catch (e) {
        // Add placeholder weather on error
        weatherList.add(TravelWeather(
          tempC: 0,
          condition: 'Unknown',
          icon: '',
          humidity: 0,
          windKph: 0,
        ));
      }
    }

    return weatherList;
  }

  /// Fetch weather for a single point
  Future<TravelWeather> _fetchWeatherForPoint(double lat, double lon) async {
    final json = await OpenMeteoService.fetchWeather(lat, lon);
    if (json == null) throw Exception('Weather fetch failed');

    final current = json['current'] as Map<String, dynamic>?;
    if (current == null) throw Exception('No current weather');

    final weatherCode = current['weather_code'] ?? 0;
    final isDay = current['is_day'] == 1;
    final condition = OpenMeteoService.getWeatherDescription(weatherCode);
    final icon = OpenMeteoService.getWeatherIcon(weatherCode, isDay);

    // Get rain chance from hourly if available
    double? rainChance;
    final hourly = json['hourly'] as Map<String, dynamic>?;
    if (hourly != null) {
      final precipProb = hourly['precipitation_probability'] as List?;
      if (precipProb != null && precipProb.isNotEmpty) {
        rainChance = (precipProb[0] as num?)?.toDouble();
      }
    }

    return TravelWeather(
      tempC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
      condition: condition,
      icon: icon,
      humidity: (current['relative_humidity_2m'] as num?)?.toInt() ?? 0,
      windKph: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
      rainChance: rainChance,
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
