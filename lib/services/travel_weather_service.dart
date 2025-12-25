// lib/services/travel_weather_service.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/motorway_point.dart';
import '../secrets.dart';

/// Simple lat/lng class for route points (renamed to avoid conflict with google_maps_flutter)
class RouteLatLng {
  final double latitude;
  final double longitude;

  const RouteLatLng(this.latitude, this.longitude);

  Map<String, dynamic> toJson() => {'lat': latitude, 'lon': longitude};

  factory RouteLatLng.fromJson(Map<String, dynamic> json) =>
      RouteLatLng(json['lat'] as double, json['lon'] as double);
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

  Map<String, dynamic> toJson() => {
        'instruction': instruction,
        'maneuver': maneuver,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'startLocation': startLocation.toJson(),
        'endLocation': endLocation.toJson(),
        'roadName': roadName,
      };

  factory NavigationStep.fromJson(Map<String, dynamic> json) => NavigationStep(
        instruction: json['instruction'] as String,
        maneuver: json['maneuver'] as String,
        distanceMeters: json['distanceMeters'] as int,
        durationSeconds: json['durationSeconds'] as int,
        startLocation:
            RouteLatLng.fromJson(json['startLocation'] as Map<String, dynamic>),
        endLocation:
            RouteLatLng.fromJson(json['endLocation'] as Map<String, dynamic>),
        roadName: json['roadName'] as String?,
      );
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

  Map<String, dynamic> toJson() => {
        'polylinePoints': polylinePoints.map((p) => p.toJson()).toList(),
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'polylineEncoded': polylineEncoded,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory RouteData.fromJson(Map<String, dynamic> json) => RouteData(
        polylinePoints: (json['polylinePoints'] as List)
            .map((p) => RouteLatLng.fromJson(p as Map<String, dynamic>))
            .toList(),
        distanceMeters: json['distanceMeters'] as int,
        durationSeconds: json['durationSeconds'] as int,
        polylineEncoded: json['polylineEncoded'] as String?,
        steps: (json['steps'] as List?)
                ?.map((s) => NavigationStep.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Cached route wrapper with expiry
class _CachedRoute {
  final RouteData route;
  final DateTime cachedAt;
  static const int _cacheExpiryDays = 7;

  _CachedRoute(this.route) : cachedAt = DateTime.now();

  _CachedRoute.fromJson(Map<String, dynamic> json)
      : route = RouteData.fromJson(json['route'] as Map<String, dynamic>),
        cachedAt = DateTime.parse(json['cachedAt'] as String);

  Map<String, dynamic> toJson() => {
        'route': route.toJson(),
        'cachedAt': cachedAt.toIso8601String(),
      };

  bool get isValid =>
      DateTime.now().difference(cachedAt).inDays < _cacheExpiryDays;
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

  // ===== ROUTE CACHING (7-day offline support) =====

  // Cache version - increment to invalidate old caches with U-turn issues
  static const String _routeCachePrefix = 'route_cache_v2_';
  
  // Full motorway endpoint coordinates are now dynamically fetched from motorway points data

  /// Generate a cache key for a route
  String _getRouteCacheKey(double startLat, double startLon, double endLat, double endLon) {
    // Round to 3 decimal places (~100m precision) for cache key matching
    final sLat = startLat.toStringAsFixed(3);
    final sLon = startLon.toStringAsFixed(3);
    final eLat = endLat.toStringAsFixed(3);
    final eLon = endLon.toStringAsFixed(3);
    return '$_routeCachePrefix${sLat}_${sLon}_to_${eLat}_$eLon';
  }
  
  /// Get cache key for full motorway route
  String _getFullMotorwayCacheKey(String motorwayId, bool forward) {
    return '${_routeCachePrefix}full_${motorwayId}_${forward ? 'fwd' : 'rev'}';
  }
  
  /// Identify which motorway a route belongs to and if it's a sub-route
  /// Returns: {'motorway': 'm2', 'forward': true, 'startIndex': 0, 'endIndex': 5}
  /// or null if not on a known motorway
  Map<String, dynamic>? _identifyMotorwayRoute(
    double startLat, double startLon, double endLat, double endLon,
    List<MotorwayPoint> routePoints,
  ) {
    if (routePoints.isEmpty) return null;
    
    final firstPoint = routePoints.first;
    final lastPoint = routePoints.last;
    
    // Determine motorway based on point IDs
    String? motorwayId;
    if (firstPoint.id.startsWith('m2_') || lastPoint.id.startsWith('m2_')) {
      motorwayId = 'm2';
    } else if (firstPoint.id.startsWith('m1_') || lastPoint.id.startsWith('m1_')) {
      motorwayId = 'm1';
    }
    
    if (motorwayId == null) return null;
    
    // Get full motorway points
    final fullPoints = motorwayId == 'm2' ? M2Motorway.points : M1Motorway.points;
    
    // Find indices in full motorway
    int startIdx = -1, endIdx = -1;
    for (int i = 0; i < fullPoints.length; i++) {
      if (fullPoints[i].id == firstPoint.id) startIdx = i;
      if (fullPoints[i].id == lastPoint.id) endIdx = i;
    }
    
    if (startIdx < 0 || endIdx < 0) return null;
    
    final isForward = startIdx < endIdx;
    
    return {
      'motorway': motorwayId,
      'forward': isForward,
      'startIndex': isForward ? startIdx : endIdx,
      'endIndex': isForward ? endIdx : startIdx,
      'fullPoints': fullPoints,
    };
  }
  
  /// Try to get a sub-route from a cached full motorway route
  Future<RouteData?> _getSubRouteFromFullCache(
    double startLat, double startLon, double endLat, double endLon,
    List<MotorwayPoint> routePoints,
  ) async {
    debugPrint('🔍 Checking for cached sub-route: ${routePoints.first.name} → ${routePoints.last.name}');
    
    final info = _identifyMotorwayRoute(startLat, startLon, endLat, endLon, routePoints);
    if (info == null) {
      debugPrint('⚠️ Could not identify motorway route');
      return null;
    }
    
    final motorwayId = info['motorway'] as String;
    final isForward = info['forward'] as bool;
    final startIdx = info['startIndex'] as int;
    final endIdx = info['endIndex'] as int;
    final fullPoints = info['fullPoints'] as List<MotorwayPoint>;
    
    debugPrint('🛣️ Identified: $motorwayId ${isForward ? 'forward' : 'reverse'}, indices $startIdx→$endIdx');
    
    // Check if we have the full motorway route cached
    final fullCacheKey = _getFullMotorwayCacheKey(motorwayId, isForward);
    debugPrint('🔑 Looking for cache key: $fullCacheKey');
    final fullRoute = await _loadRouteFromCache(fullCacheKey);
    
    if (fullRoute == null) {
      debugPrint('📂 No cached full route for $motorwayId (${isForward ? 'forward' : 'reverse'})');
      return null;
    }
    
    // Check if this is the full route (no trimming needed)
    if (startIdx == 0 && endIdx == fullPoints.length - 1) {
      debugPrint('📂 Using full cached $motorwayId route');
      return fullRoute;
    }
    
    // Trim the polyline to match the sub-route
    final startPoint = fullPoints[startIdx];
    final endPoint = fullPoints[endIdx];
    
    // Find polyline indices that match our start/end latitudes
    final trimmedPoints = _trimPolylineToSegment(
      fullRoute.polylinePoints,
      startPoint.lat, startPoint.lon,
      endPoint.lat, endPoint.lon,
      isForward,
    );
    
    if (trimmedPoints == null || trimmedPoints.isEmpty) {
      debugPrint('⚠️ Failed to trim polyline for sub-route');
      return null;
    }
    
    // Calculate approximate distance/duration for sub-route
    final fullDistanceKm = motorwayId == 'm2' ? 367.0 : 155.0;
    final segmentDistanceKm = (endPoint.distanceFromStart - startPoint.distanceFromStart).abs().toDouble();
    final fraction = segmentDistanceKm / fullDistanceKm;
    
    debugPrint('✂️ Trimmed $motorwayId route: ${startPoint.name} → ${endPoint.name} (${trimmedPoints.length} points, ${segmentDistanceKm.round()}km)');
    
    return RouteData(
      polylinePoints: trimmedPoints,
      distanceMeters: (segmentDistanceKm * 1000).round(),
      durationSeconds: (fullRoute.durationSeconds * fraction).round(),
      steps: [], // Steps won't be accurate for sub-routes
    );
  }
  
  /// Trim polyline points to match a segment between start and end coordinates
  /// Uses latitude-based trimming since motorways generally go north-south
  List<RouteLatLng>? _trimPolylineToSegment(
    List<RouteLatLng> points,
    double startLat, double startLon,
    double endLat, double endLon,
    bool isForward,
  ) {
    if (points.isEmpty) return null;
    
    debugPrint('🔄 Trimming polyline: ${points.length} points, start=($startLat), end=($endLat), forward=$isForward');
    
    // For forward routes (going south, ISB→LHR), we go from higher lat to lower lat
    // For reverse routes (going north, LHR→ISB), we go from lower lat to higher lat
    
    int startIdx = -1;
    int endIdx = -1;
    
    // Find start point: first point close enough to start coordinates
    const double toleranceKm = 2.0; // 2km tolerance for matching
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final dist = _haversineDistance(p.latitude, p.longitude, startLat, startLon);
      if (dist < toleranceKm) {
        startIdx = i;
        break; // Take the first match
      }
    }
    
    // If no exact match, find closest
    if (startIdx < 0) {
      double minDist = double.infinity;
      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final dist = _haversineDistance(p.latitude, p.longitude, startLat, startLon);
        if (dist < minDist) {
          minDist = dist;
          startIdx = i;
        }
      }
    }
    
    // Find end point: search AFTER startIdx for point close to end coordinates
    // This ensures we respect the direction of travel
    final searchStart = startIdx >= 0 ? startIdx : 0;
    for (int i = searchStart; i < points.length; i++) {
      final p = points[i];
      final dist = _haversineDistance(p.latitude, p.longitude, endLat, endLon);
      if (dist < toleranceKm) {
        endIdx = i;
        break; // Take the first match after start
      }
    }
    
    // If no exact match, find closest point AFTER startIdx
    if (endIdx < 0) {
      double minDist = double.infinity;
      for (int i = searchStart; i < points.length; i++) {
        final p = points[i];
        final dist = _haversineDistance(p.latitude, p.longitude, endLat, endLon);
        if (dist < minDist) {
          minDist = dist;
          endIdx = i;
        }
      }
    }
    
    if (startIdx < 0 || endIdx < 0) {
      debugPrint('⚠️ Could not find start/end indices: startIdx=$startIdx, endIdx=$endIdx');
      return null;
    }
    
    // Ensure correct order (start before end)
    if (startIdx > endIdx) {
      final temp = startIdx;
      startIdx = endIdx;
      endIdx = temp;
    }
    
    debugPrint('✂️ Trimming: indices $startIdx→$endIdx (${endIdx - startIdx + 1} points)');
    
    return points.sublist(startIdx, endIdx + 1);
  }
  
  /// Haversine distance in km
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth's radius in km
    final dLat = (lat2 - lat1) * 3.14159 / 180;
    final dLon = (lon2 - lon1) * 3.14159 / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * 3.14159 / 180) * cos(lat2 * 3.14159 / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }
  
  /// Cache a full motorway route
  Future<void> _cacheFullMotorwayRoute(String motorwayId, bool forward, RouteData route) async {
    final key = _getFullMotorwayCacheKey(motorwayId, forward);
    await _saveRouteToCache(key, route);
    debugPrint('💾 Full $motorwayId (${forward ? 'forward' : 'reverse'}) cached: ${route.polylinePoints.length} points');
  }
  
  /// Check if route is on a motorway and cache the FULL motorway route for sub-route extraction
  /// This allows offline sub-route navigation after any route on that motorway is fetched
  Future<void> _maybeCacheAsFullMotorway(
    double startLat, double startLon, double endLat, double endLon,
    RouteData route, List<MotorwayPoint>? routePoints,
  ) async {
    if (routePoints == null || routePoints.length < 2) return;
    
    final firstPoint = routePoints.first;
    final lastPoint = routePoints.last;
    
    // Get the actual first and last IDs from the motorway data
    final m2First = M2Motorway.points.first.id; // m2_01
    final m2Last = M2Motorway.points.last.id;   // m2_20
    final m1First = M1Motorway.points.first.id;
    final m1Last = M1Motorway.points.last.id;
    
    debugPrint('🔍 Checking route: first=${firstPoint.id}, last=${lastPoint.id}');
    
    // Check if this is the full M2 route (ISB to LHR) - just cache as-is
    if (firstPoint.id == m2First && lastPoint.id == m2Last) {
      await _cacheFullMotorwayRoute('m2', true, route);
      return;
    } else if (firstPoint.id == m2Last && lastPoint.id == m2First) {
      await _cacheFullMotorwayRoute('m2', false, route);
      return;
    }
    // Check if this is the full M1 route
    else if (firstPoint.id == m1First && lastPoint.id == m1Last) {
      await _cacheFullMotorwayRoute('m1', true, route);
      return;
    } else if (firstPoint.id == m1Last && lastPoint.id == m1First) {
      await _cacheFullMotorwayRoute('m1', false, route);
      return;
    }
    
    // Not a full route - check if it's on M2 or M1 and fetch full route in background
    String? motorwayId;
    bool? isForward;
    List<MotorwayPoint>? fullPoints;
    
    if (firstPoint.id.startsWith('m2_')) {
      motorwayId = 'm2';
      fullPoints = M2Motorway.points;
      // Determine direction based on point indices
      final startIdx = fullPoints.indexWhere((p) => p.id == firstPoint.id);
      final endIdx = fullPoints.indexWhere((p) => p.id == lastPoint.id);
      isForward = startIdx < endIdx;
    } else if (firstPoint.id.startsWith('m1_')) {
      motorwayId = 'm1';
      fullPoints = M1Motorway.points;
      final startIdx = fullPoints.indexWhere((p) => p.id == firstPoint.id);
      final endIdx = fullPoints.indexWhere((p) => p.id == lastPoint.id);
      isForward = startIdx < endIdx;
    }
    
    if (motorwayId == null || fullPoints == null || isForward == null) {
      debugPrint('📂 Not a motorway route - skipping cache');
      return;
    }
    
    // Check if we already have the full route cached
    final fullCacheKey = _getFullMotorwayCacheKey(motorwayId, isForward);
    final existingCache = await _loadRouteFromCache(fullCacheKey);
    if (existingCache != null) {
      debugPrint('📂 Full $motorwayId route already cached');
      return;
    }
    
    // Fetch full motorway route in background for future sub-route extraction
    debugPrint('🌐 Fetching full $motorwayId route in background for caching...');
    _fetchAndCacheFullMotorway(motorwayId, isForward, fullPoints);
  }
  
  /// Fetch full motorway route and cache it (runs in background)
  /// Note: We fetch WITHOUT intermediate waypoints to get a clean highway route.
  /// If we pass toll plaza coordinates as waypoints, Google routes to each exact
  /// point - causing U-turns when plazas are on opposite sides of the motorway.
  Future<void> _fetchAndCacheFullMotorway(
    String motorwayId, bool isForward, List<MotorwayPoint> fullPoints,
  ) async {
    try {
      final orderedPoints = isForward ? fullPoints : fullPoints.reversed.toList();
      final start = orderedPoints.first;
      final end = orderedPoints.last;
      
      // Fetch route using ONLY start and end points - no waypoints!
      // This gives us a clean highway polyline without U-turns at toll plazas
      final fullRoute = await _fetchRouteFromApi(
        startLat: start.lat,
        startLon: start.lon,
        endLat: end.lat,
        endLon: end.lon,
        // Don't pass waypoints - let Google follow the natural highway route
      );
      
      if (fullRoute != null) {
        await _cacheFullMotorwayRoute(motorwayId, isForward, fullRoute);
        debugPrint('✅ Full $motorwayId (${isForward ? 'fwd' : 'rev'}) cached in background (clean route, no waypoints)');
      } else {
        debugPrint('⚠️ Failed to fetch full $motorwayId route in background');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching full $motorwayId route: $e');
    }
  }

  /// Save route to local storage (7-day cache)
  Future<void> _saveRouteToCache(String key, RouteData route) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = _CachedRoute(route);
      await prefs.setString(key, jsonEncode(cached.toJson()));
      debugPrint('💾 Route cached: $key (${route.polylinePoints.length} points)');
    } catch (e) {
      debugPrint('⚠️ Failed to cache route: $e');
    }
  }

  /// Load route from local storage if valid (< 7 days old)
  Future<RouteData?> _loadRouteFromCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final cached = _CachedRoute.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      if (cached.isValid) {
        final daysOld = DateTime.now().difference(cached.cachedAt).inDays;
        debugPrint('📂 Route loaded from cache: $key ($daysOld days old, ${cached.route.polylinePoints.length} points)');
        return cached.route;
      } else {
        // Expired - remove from cache
        await prefs.remove(key);
        debugPrint('🗑️ Expired route cache removed: $key');
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load route cache: $e');
      return null;
    }
  }

  /// Clear all cached routes
  Future<void> clearRouteCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_routeCachePrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
      debugPrint('🗑️ All route caches cleared (${keys.length} routes)');
    } catch (e) {
      debugPrint('⚠️ Failed to clear route cache: $e');
    }
  }

  // ===== END ROUTE CACHING =====

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
  /// Routes are cached locally for 7 days for offline use
  /// Smart caching: If full motorway route is cached, sub-routes are trimmed from it
  Future<RouteData?> getRoutePolyline({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    List<MotorwayPoint>? waypoints,
    bool forceRefresh = false,
  }) async {
    // Check exact route cache first (unless forced refresh)
    final cacheKey = _getRouteCacheKey(startLat, startLon, endLat, endLon);
    if (!forceRefresh) {
      final cachedRoute = await _loadRouteFromCache(cacheKey);
      if (cachedRoute != null) {
        return cachedRoute;
      }
      
      // Try to get sub-route from cached full motorway route
      if (waypoints != null && waypoints.isNotEmpty) {
        final subRoute = await _getSubRouteFromFullCache(
          startLat, startLon, endLat, endLon, waypoints,
        );
        if (subRoute != null) {
          // Cache this sub-route for future exact matches
          await _saveRouteToCache(cacheKey, subRoute);
          return subRoute;
        }
      }
    }

    try {
      // IMPORTANT: For motorway routes, we DON'T pass intermediate waypoints to Google!
      // If we pass toll plaza coordinates as waypoints, Google routes to each exact point,
      // causing U-turns when plazas are on opposite sides of the motorway.
      // Instead, we just use start and end points - Google will follow the highway naturally.
      
      // Check if this is a motorway route (has waypoints from motorway points list)
      final isMotorwayRoute = waypoints != null && waypoints.isNotEmpty;
      
      RouteData? routeData;

      // For motorway routes: fetch with ONLY start/end (no intermediate waypoints)
      // For other routes: use waypoints if provided
      routeData = await _fetchRouteFromApi(
        startLat: startLat,
        startLon: startLon,
        endLat: endLat,
        endLon: endLon,
        waypoints: isMotorwayRoute ? null : waypoints, // No waypoints for motorway routes!
      );

      // Cache the route for offline use
      if (routeData != null) {
        await _saveRouteToCache(cacheKey, routeData);
        
        // Also cache as full motorway route if applicable (for sub-route trimming)
        await _maybeCacheAsFullMotorway(startLat, startLon, endLat, endLon, routeData, waypoints);
      }

      return routeData;
    } catch (e) {
      debugPrint('Error fetching route polyline: $e');
      // Try to return cached route even if expired
      final cachedRoute = await _loadRouteFromCache(cacheKey);
      if (cachedRoute != null) {
        debugPrint('📂 Using expired cache as fallback');
        return cachedRoute;
      }
      return null;
    }
  }

  /// Fetch route directly from Google Directions API (single segment)
  Future<RouteData?> _fetchRouteFromApi({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    List<MotorwayPoint>? waypoints,
  }) async {
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
