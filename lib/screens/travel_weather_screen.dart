// lib/screens/travel_weather_screen.dart

import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/motorway_point.dart';
import '../services/travel_weather_service.dart';
import '../services/prayer_service.dart';
import '../metar_service.dart';
import '../services/weather_controller.dart';

class TravelWeatherScreen extends StatefulWidget {
  final bool isDay;

  const TravelWeatherScreen({super.key, this.isDay = true});

  @override
  State<TravelWeatherScreen> createState() => _TravelWeatherScreenState();
}

class _TravelWeatherScreenState extends State<TravelWeatherScreen>
    with SingleTickerProviderStateMixin {
  // View toggle: 0 = Timeline, 1 = Map
  int _currentView = 0;

  // Navigation state
  bool _routeConfirmed = false; // NEW: Only load data after user confirms route
  bool _isNavigating = false; // NEW: Real-time navigation mode
  double _currentSpeed = 0.0; // Current speed in km/h

  // Cache settings
  static const int _cacheMinutes = 15; // Cache duration in minutes

  // Motorway selection
  String _selectedMotorwayId = 'm2'; // Default to M2 (Islamabad-Lahore)

  // Search state
  String? _fromId; // null means current location
  String? _toId;
  bool _showFromSearch = false;
  bool _showToSearch = false;
  final TextEditingController _fromSearchController = TextEditingController();
  final TextEditingController _toSearchController = TextEditingController();

  // Route data
  List<TravelPoint> _routePoints = [];
  bool _isLoading = false;
  String? _error;

  // Current location
  Position? _currentPosition;
  Map<String, dynamic>? _currentLocationWeather;
  Map<String, dynamic>? _currentLocationMetar;

  // METAR data for route points
  Map<String, Map<String, dynamic>?> _metarData = {};

  // Map controller
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // Real road route from Google Directions API
  List<LatLng> _roadRoutePoints = [];
  int _routeDistanceMeters = 0;
  int _routeDurationSeconds = 0;
  List<NavigationStep> _navigationSteps = []; // Turn-by-turn instructions
  int _currentStepIndex = 0; // Current navigation step

  // Real-time navigation tracking
  StreamSubscription<Position>? _positionStream;
  int _currentPointIndex = 0; // Track which point user has passed
  bool _useCarIcon = false; // false = arrow (like Google Maps), true = car icon
  double _currentHeading =
      0; // Direction user is facing (from GPS or calculated)
  double _roadBearing =
      0; // Bearing calculated from road polyline (more accurate)
  bool _isFollowingUser = true; // Whether map is auto-following user location
  int _closestPolylineIndex = 0; // Index of closest point on polyline

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Blue theme colors
  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _lightBlue = Color(0xFF42A5F5);
  static const Color _darkBlue = Color(0xFF0D47A1);
  static const Color _accentBlue = Color(0xFF64B5F6);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    // Don't set default destination - let user choose
    _toId = null;

    // Just get current location, don't load route yet
    _initializeLocation();
  }

  @override
  void dispose() {
    _animController.dispose();
    _fromSearchController.dispose();
    _toSearchController.dispose();
    _mapController?.dispose();
    _positionStream?.cancel(); // Cancel location tracking
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoading = true);

    try {
      // Battery optimization: medium accuracy for initial position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      _currentPosition = position;
      // DON'T load route here - wait for user to confirm destination
    } catch (e) {
      setState(() => _error = 'Failed to get location: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Called when user taps "Start Journey" button
  Future<void> _confirmRouteAndLoad() async {
    if (_toId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination')),
      );
      return;
    }

    setState(() {
      _routeConfirmed = true;
      _isLoading = true;
    });

    // Fetch current location weather
    await _fetchCurrentLocationWeather();

    // Load route data
    await _loadRoute();
  }

  /// Start real-time navigation tracking
  void _startNavigation() {
    if (_isNavigating) return;

    setState(() {
      _isNavigating = true;
      _isFollowingUser = true; // Start following user when navigation begins
    });
    _currentPointIndex = 0;

    // Start listening to location updates
    // Battery optimization: use medium accuracy and larger distance filter
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium, // Saves battery vs high
        distanceFilter: 150, // Update every 150 meters - reduces GPS calls
      ),
    ).listen(_onLocationUpdate);
  }

  /// Stop navigation
  void _stopNavigation() {
    _positionStream?.cancel();
    _positionStream = null;
    setState(() {
      _isNavigating = false;
      _isFollowingUser = true; // Reset for next navigation
    });
  }

  /// Handle location updates during navigation
  void _onLocationUpdate(Position position) {
    _currentPosition = position;

    // Update speed (convert m/s to km/h)
    _currentSpeed = (position.speed * 3.6).clamp(0, 300);

    // Update heading from GPS if moving fast enough
    if (position.heading >= 0 && position.speed > 2) {
      _currentHeading = position.heading;
    }

    // Calculate road bearing from polyline (more accurate for display)
    _calculateRoadBearing(position);

    // Check if user has passed any points
    for (int i = _currentPointIndex; i < _routePoints.length; i++) {
      final point = _routePoints[i].point;
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        point.lat,
        point.lon,
      );

      // If within 500m of a point, mark it as passed
      if (distance < 500) {
        _currentPointIndex = i + 1;
        // Save progress
        _saveNavigationProgress();
      }
    }

    // Update current navigation step based on position
    _updateCurrentNavigationStep(position);

    // Update map camera to follow user with compass effect (check if controller is still valid)
    if (_mapController != null && mounted && _isFollowingUser) {
      try {
        // Use road bearing for smoother navigation (falls back to GPS heading)
        final bearing = _roadBearing != 0 ? _roadBearing : _currentHeading;

        // Calculate offset target to show more road ahead (like Google Maps)
        // Move camera target slightly ahead in the direction of travel
        final offsetDistance = 0.0008; // ~80 meters ahead
        final radians = bearing * (3.14159265359 / 180);
        final aheadLat = position.latitude + (offsetDistance * cos(radians));
        final aheadLon = position.longitude +
            (offsetDistance *
                sin(radians) /
                cos(position.latitude * 3.14159265359 / 180));

        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(aheadLat, aheadLon), // Look ahead
              zoom: 18, // Closer zoom for better road visibility
              bearing: bearing, // Use road bearing for smooth rotation
              tilt: 60, // More tilt for immersive 3D view like Google Maps
            ),
          ),
        );
      } catch (_) {
        // Controller may have been disposed
      }
    }

    _updateMapMarkers();
    if (mounted) setState(() {});
  }

  /// Calculate road bearing from polyline for smoother navigation
  /// This gives more accurate direction than GPS heading when following the road
  void _calculateRoadBearing(Position position) {
    if (_roadRoutePoints.length < 2) return;

    // Find closest point on polyline
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < _roadRoutePoints.length; i++) {
      final point = _roadRoutePoints[i];
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    _closestPolylineIndex = closestIndex;

    // Calculate bearing to next point on polyline (look ahead for smoother rotation)
    // Look 3-5 points ahead for smoother bearing
    final lookAhead = min(closestIndex + 5, _roadRoutePoints.length - 1);
    if (lookAhead > closestIndex) {
      final currentPoint = _roadRoutePoints[closestIndex];
      final nextPoint = _roadRoutePoints[lookAhead];

      _roadBearing = Geolocator.bearingBetween(
        currentPoint.latitude,
        currentPoint.longitude,
        nextPoint.latitude,
        nextPoint.longitude,
      );
    }
  }

  /// Update which navigation step we're currently on
  void _updateCurrentNavigationStep(Position position) {
    if (_navigationSteps.isEmpty) return;

    for (int i = _currentStepIndex; i < _navigationSteps.length; i++) {
      final step = _navigationSteps[i];
      final distanceToEnd = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        step.endLocation.latitude,
        step.endLocation.longitude,
      );

      // If within 50m of step end, move to next step
      if (distanceToEnd < 50) {
        _currentStepIndex = i + 1;
      } else {
        break;
      }
    }
  }

  Future<void> _fetchCurrentLocationWeather() async {
    if (_currentPosition == null) return;

    try {
      // Check if there's a nearby airport for METAR
      final airport = WeatherController().getAirportFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (airport != null) {
        _currentLocationMetar = await fetchMetar(airport['icao']);
      }

      // Fetch weather from OpenMeteo
      final weather = await TravelWeatherService.instance.getWeatherForPoints([
        MotorwayPoint(
          id: 'current',
          name: 'Current Location',
          lat: _currentPosition!.latitude,
          lon: _currentPosition!.longitude,
          type: PointType.interchange,
          distanceFromStart: 0,
        ),
      ]);

      if (weather.isNotEmpty) {
        _currentLocationWeather = {
          'temp_c': weather[0].tempC,
          'humidity': weather[0].humidity,
          'wind_kph': weather[0].windKph,
          'condition': weather[0].condition,
          'icon': weather[0].icon,
        };
      }
    } catch (e) {
      debugPrint('Error fetching current location weather: $e');
    }
  }

  /// Get key points for weather fetching (start, service areas, destination)
  /// This optimizes API calls by not fetching weather for every toll plaza
  List<MotorwayPoint> _getKeyPointsForWeather(List<MotorwayPoint> allPoints) {
    // Return ALL points - user wants weather visible for every toll plaza/interchange
    return allPoints;
  }

  /// Get which prayer will be active when user arrives at a location
  /// Returns the CURRENT prayer at arrival time (not the next one)
  Future<Map<String, String?>> _getPrayerAtArrivalTime({
    required double latitude,
    required double longitude,
    required DateTime arrivalTime,
  }) async {
    final prayerTimes = await PrayerService.calculatePrayerTimes(
      latitude: latitude,
      longitude: longitude,
      date: arrivalTime,
    );

    // Get all prayers for that day
    final prayers = prayerTimes.prayers;

    // Find which prayer period the arrival time falls into
    // Prayer periods: Fajr → Sunrise, Dhuhr → Asr, Asr → Maghrib, Maghrib → Isha, Isha → Fajr
    String? activePrayerName;
    String? activePrayerTime;

    for (int i = prayers.length - 1; i >= 0; i--) {
      final prayer = prayers[i];
      // Skip Sunrise as it's not a prayer time
      if (prayer.name == 'Sunrise') continue;

      // If arrival time is after this prayer time, this is the active prayer
      if (arrivalTime.isAfter(prayer.time) ||
          arrivalTime.isAtSameMomentAs(prayer.time)) {
        activePrayerName = prayer.name;
        activePrayerTime = prayer.formattedTime;
        break;
      }
    }

    // If no prayer found (before Fajr), it's still Isha from previous night
    if (activePrayerName == null) {
      // Before Fajr - show Isha (or next Fajr time)
      final fajr = prayers.firstWhere((p) => p.name == 'Fajr');
      activePrayerName = 'Before Fajr';
      activePrayerTime = 'Fajr at ${fajr.formattedTime}';
    }

    return {
      'name': activePrayerName,
      'time': activePrayerTime,
    };
  }

  // Flag to prevent duplicate loads
  bool _isLoadingRoute = false;

  Future<void> _loadRoute() async {
    if (_toId == null) return;

    // Prevent duplicate loads
    if (_isLoadingRoute) {
      return;
    }
    _isLoadingRoute = true;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Try to load from cache first (15 min valid)
      final cacheLoaded = await _loadCachedRouteData();
      if (cacheLoaded) {
        _updateMapMarkers();
        await _loadNavigationProgress();
        _isLoadingRoute = false;
        setState(() => _isLoading = false);
        return;
      }

      // Get points for the route
      List<MotorwayPoint> points;
      if (_fromId == null) {
        // From current location to destination
        // Get all points to destination first
        final allPoints =
            PakistanMotorways.getPointsTo(_selectedMotorwayId, _toId!);

        // Find the nearest toll plaza that's on the way to destination
        // (not behind us requiring backtracking)
        if (_currentPosition != null && allPoints.length > 1) {
          points = _filterPointsOnRoute(allPoints);
        } else {
          points = allPoints;
        }
      } else {
        // Between two toll plazas
        points = PakistanMotorways.getPointsBetween(
            _selectedMotorwayId, _fromId!, _toId!);
      }

      if (points.isEmpty) {
        setState(() => _error = 'No route found');
        return;
      }

      // Get starting coordinates
      final startLat = _currentPosition?.latitude ?? points.first.lat;
      final startLon = _currentPosition?.longitude ?? points.first.lon;
      final endLat = points.last.lat;
      final endLon = points.last.lon;

      // FETCH ACTUAL ROAD ROUTE FROM GOOGLE DIRECTIONS API
      // NOTE: We do NOT pass toll plazas as waypoints because they are slightly
      // off the motorway. Passing them causes zig-zag routes (go to toll, go back).
      // Instead, just route from start to end directly on the motorway.
      // Toll plazas are used only for markers and weather/ETA calculations.
      final routeData = await TravelWeatherService.instance.getRoutePolyline(
        startLat: startLat,
        startLon: startLon,
        endLat: endLat,
        endLon: endLon,
        // Don't pass waypoints - route directly on motorway
        waypoints: null,
      );

      if (routeData != null) {
        // Convert to Google Maps LatLng
        _roadRoutePoints = routeData.polylinePoints
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
        _routeDistanceMeters = routeData.distanceMeters;
        _routeDurationSeconds = routeData.durationSeconds;
        _navigationSteps = routeData.steps; // Store turn-by-turn instructions
        debugPrint(
            '✅ Got ${_roadRoutePoints.length} road polyline points from API');
      } else {
        // Fallback to straight lines between points
        _roadRoutePoints = [
          LatLng(startLat, startLon),
          ...points.map((p) => LatLng(p.lat, p.lon)),
        ];
        _navigationSteps = [];
        debugPrint(
            '⚠️ Using fallback straight lines (${_roadRoutePoints.length} points)');
      }

      // Fetch weather for ALL route points
      final keyPoints = _getKeyPointsForWeather(points);
      final weatherList =
          await TravelWeatherService.instance.getWeatherForPoints(keyPoints);

      // Create a map of weather by point ID for quick lookup
      final weatherMap = <String, TravelWeather>{};
      for (int i = 0; i < keyPoints.length && i < weatherList.length; i++) {
        weatherMap[keyPoints[i].id] = weatherList[i];
      }

      // Calculate ETAs from route data or estimate
      List<Duration> etas = [];
      if (routeData != null) {
        // Use actual route duration, distribute across points
        final totalSeconds = routeData.durationSeconds;
        final totalDistance = routeData.distanceMeters / 1000; // km

        for (int i = 0; i < points.length; i++) {
          final pointDistance = points[i].distanceFromStart.toDouble();
          final fraction =
              totalDistance > 0 ? pointDistance / totalDistance : 0.0;
          final seconds = (totalSeconds * fraction).round();
          etas.add(Duration(seconds: seconds));
        }
      } else {
        // Use distance-based estimation (100 km/h average on motorway)
        etas = points.map((p) {
          final minutes = (p.distanceFromStart / 100 * 60).round();
          return Duration(minutes: minutes);
        }).toList();
      }

      // Build travel points with weather AND prayer times for all points
      final now = DateTime.now();
      final travelPoints = <TravelPoint>[];

      for (int i = 0; i < points.length; i++) {
        final point = points[i];
        final eta = i < etas.length ? etas[i] : null;
        final weather = weatherMap[point.id];
        final estimatedArrival = eta != null ? now.add(eta) : null;

        // Calculate which prayer will be active when you ARRIVE at this point
        String? activePrayer;
        String? activePrayerTime;

        if (estimatedArrival != null) {
          try {
            final prayerData = await _getPrayerAtArrivalTime(
              latitude: point.lat,
              longitude: point.lon,
              arrivalTime: estimatedArrival,
            );
            activePrayer = prayerData['name'];
            activePrayerTime = prayerData['time'];
          } catch (_) {
            // Prayer calculation failed, continue without it
          }
        }

        travelPoints.add(TravelPoint(
          point: point,
          etaFromStart: eta,
          estimatedArrival: estimatedArrival,
          weather: weather,
          nextPrayer: activePrayer,
          nextPrayerTime: activePrayerTime,
        ));
      }

      _routePoints = travelPoints;

      // Fetch METAR data for points near airports
      await _fetchMetarForRoute();

      // Update map
      _updateMapMarkers();

      // Cache the route data
      await _cacheRouteData();
    } catch (e) {
      setState(() => _error = 'Failed to load route: $e');
    } finally {
      _isLoadingRoute = false;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMetarForRoute() async {
    final prefs = await SharedPreferences.getInstance();

    for (final tp in _routePoints) {
      final cacheKey = 'metar_${tp.point.id}';

      // Check cache first
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final data = jsonDecode(cached);
        final fetchedAt = DateTime.parse(data['fetched_at']);
        if (DateTime.now().difference(fetchedAt).inMinutes < 20) {
          _metarData[tp.point.id] = data['metar'];
          continue;
        }
      }

      // Check if there's a nearby airport
      final airport = WeatherController().getAirportFromCoordinates(
        tp.point.lat,
        tp.point.lon,
      );

      if (airport != null) {
        try {
          final metar = await fetchMetar(airport['icao']);
          _metarData[tp.point.id] = metar;

          // Cache it
          if (metar != null) {
            await prefs.setString(
              cacheKey,
              jsonEncode({
                'fetched_at': DateTime.now().toIso8601String(),
                'metar': metar,
              }),
            );
          }
        } catch (e) {
          debugPrint('METAR fetch error for ${tp.point.name}: $e');
        }
      }
    }

    setState(() {});
  }

  /// Get cache key for current route (per-route caching)
  String _getRouteCacheKey() {
    final from = _fromId ?? 'current';
    return 'travel_route_cache_${_selectedMotorwayId}_${from}_$_toId';
  }

  /// Cache route data with weather, prayer times for 15 minutes
  Future<void> _cacheRouteData() async {
    final prefs = await SharedPreferences.getInstance();

    // Serialize route points with all data
    final pointsData = _routePoints
        .map((tp) => {
              'point_id': tp.point.id,
              'point_name': tp.point.name,
              'lat': tp.point.lat,
              'lon': tp.point.lon,
              'type': tp.point.type.index,
              'distance': tp.point.distanceFromStart,
              'facilities': tp.point.facilities,
              'eta_minutes': tp.etaFromStart?.inMinutes,
              'arrival_iso': tp.estimatedArrival?.toIso8601String(),
              'weather': tp.weather != null
                  ? {
                      'temp_c': tp.weather!.tempC,
                      'condition': tp.weather!.condition,
                      'icon': tp.weather!.icon,
                      'humidity': tp.weather!.humidity,
                      'wind_kph': tp.weather!.windKph,
                      'rain_chance': tp.weather!.rainChance,
                    }
                  : null,
              'next_prayer': tp.nextPrayer,
              'next_prayer_time': tp.nextPrayerTime,
            })
        .toList();

    final cacheData = {
      'motorway_id': _selectedMotorwayId,
      'from_id': _fromId,
      'to_id': _toId,
      'cached_at': DateTime.now().toIso8601String(),
      'route_points': pointsData,
      'road_route': _roadRoutePoints
          .map((p) => {'lat': p.latitude, 'lon': p.longitude})
          .toList(),
      'distance_meters': _routeDistanceMeters,
      'duration_seconds': _routeDurationSeconds,
      'metar_data': _metarData.map((k, v) => MapEntry(k, v)),
    };

    // Use route-specific cache key
    final cacheKey = _getRouteCacheKey();
    await prefs.setString(cacheKey, jsonEncode(cacheData));
  }

  /// Load cached route data if available and not expired (15 min)
  Future<bool> _loadCachedRouteData() async {
    final prefs = await SharedPreferences.getInstance();

    // Use route-specific cache key
    final cacheKey = _getRouteCacheKey();
    final cached = prefs.getString(cacheKey);

    if (cached == null) {
      return false;
    }

    try {
      final data = jsonDecode(cached) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(data['cached_at']);
      final cacheAge = DateTime.now().difference(cachedAt).inMinutes;

      // Check if cache is expired (15 minutes)
      if (cacheAge > _cacheMinutes) {
        return false;
      }

      // Restore route points
      final pointsData = data['route_points'] as List<dynamic>;
      _routePoints = pointsData.map((p) {
        final point = MotorwayPoint(
          id: p['point_id'],
          name: p['point_name'],
          lat: p['lat'],
          lon: p['lon'],
          type: PointType.values[p['type']],
          distanceFromStart: p['distance'],
          facilities: p['facilities'],
        );

        TravelWeather? weather;
        if (p['weather'] != null) {
          final w = p['weather'];
          weather = TravelWeather(
            tempC: (w['temp_c'] as num).toDouble(),
            condition: w['condition'],
            icon: w['icon'],
            humidity: w['humidity'],
            windKph: (w['wind_kph'] as num).toDouble(),
            rainChance: w['rain_chance'] != null
                ? (w['rain_chance'] as num).toDouble()
                : null,
          );
        }

        return TravelPoint(
          point: point,
          etaFromStart: p['eta_minutes'] != null
              ? Duration(minutes: p['eta_minutes'])
              : null,
          estimatedArrival: p['arrival_iso'] != null
              ? DateTime.parse(p['arrival_iso'])
              : null,
          weather: weather,
          nextPrayer: p['next_prayer'],
          nextPrayerTime: p['next_prayer_time'],
        );
      }).toList();

      // Restore road route
      final roadData = data['road_route'] as List<dynamic>;
      _roadRoutePoints =
          roadData.map((p) => LatLng(p['lat'], p['lon'])).toList();
      _routeDistanceMeters = data['distance_meters'] ?? 0;
      _routeDurationSeconds = data['duration_seconds'] ?? 0;

      // Restore METAR data
      if (data['metar_data'] != null) {
        final metarMap = data['metar_data'] as Map<String, dynamic>;
        _metarData = metarMap.map((k, v) =>
            MapEntry(k, v != null ? Map<String, dynamic>.from(v) : null));
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Save navigation progress
  Future<void> _saveNavigationProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('nav_current_point_index', _currentPointIndex);
    await prefs.setBool('nav_is_navigating', _isNavigating);
    await prefs.setString('nav_route_id', '${_fromId ?? "current"}_to_$_toId');
  }

  /// Load navigation progress
  Future<void> _loadNavigationProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRouteId = prefs.getString('nav_route_id');
    final currentRouteId = '${_fromId ?? "current"}_to_$_toId';

    if (savedRouteId == currentRouteId) {
      _currentPointIndex = prefs.getInt('nav_current_point_index') ?? 0;
      final wasNavigating = prefs.getBool('nav_is_navigating') ?? false;
      if (wasNavigating && _currentPointIndex < _routePoints.length) {
        // Resume navigation
        _startNavigation();
      }
    }
  }

  void _updateMapMarkers() {
    _markers.clear();
    _polylines.clear();

    // Add current location marker with navigation arrow
    if (_currentPosition != null) {
      // Use road bearing for marker rotation (more aligned with road)
      final markerBearing = _roadBearing != 0 ? _roadBearing : _currentHeading;

      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          // Use cyan/blue for navigation marker like Google Maps
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: const InfoWindow(title: '📍 You'),
          rotation: markerBearing, // Rotate based on road direction
          anchor: const Offset(0.5, 0.5), // Center the marker
          flat: true, // Make marker flat on map so rotation works properly
          zIndex: 100, // Show on top of other markers
        ),
      );
    }

    // Add route point markers with navigation state
    for (int i = 0; i < _routePoints.length; i++) {
      final tp = _routePoints[i];
      final isPassed = _isNavigating && i < _currentPointIndex;
      final isNext = _isNavigating && i == _currentPointIndex;

      // Determine marker color based on state
      double hue;
      if (isPassed) {
        hue = BitmapDescriptor.hueViolet; // Passed points in purple
      } else if (isNext) {
        hue = BitmapDescriptor.hueCyan; // Next point in cyan
      } else if (tp.point.type == PointType.destination) {
        hue = BitmapDescriptor.hueGreen;
      } else if (tp.point.type == PointType.serviceArea) {
        hue = BitmapDescriptor.hueOrange;
      } else {
        hue = BitmapDescriptor.hueRed;
      }

      _markers.add(
        Marker(
          markerId: MarkerId(tp.point.id),
          position: LatLng(tp.point.lat, tp.point.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          alpha: isPassed ? 0.5 : 1.0, // Fade passed points
          infoWindow: InfoWindow(
            title: tp.point.name,
            snippet: tp.weather != null
                ? '${tp.weather!.tempC.round()}°C - ${tp.weather!.condition}'
                : isPassed
                    ? 'Passed'
                    : null,
          ),
        ),
      );
    }

    // USE REAL ROAD POLYLINE FROM GOOGLE DIRECTIONS API
    if (_roadRoutePoints.isNotEmpty) {
      // Determine how much of the route has been traveled
      // Use closestPolylineIndex for passed route (already calculated)
      int passedIndex = _closestPolylineIndex;
      if (!_isNavigating) {
        passedIndex = 0;
      }

      // Draw route border (dark outline) for better visibility - like Google Maps
      if (_roadRoutePoints.length >= 2) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route_border'),
            points: _roadRoutePoints,
            color: const Color(0xFF0D47A1), // Dark blue border
            width: 10, // Wider for border effect
            patterns: [],
          ),
        );
      }

      // Draw the passed portion of the route (completed - teal/green)
      if (_isNavigating && passedIndex > 0) {
        final passedPoints = _roadRoutePoints.sublist(0, passedIndex + 1);
        // Border for passed section
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('passed_border'),
            points: passedPoints,
            color: const Color(0xFF00695C), // Dark teal border
            width: 10,
            patterns: [],
          ),
        );
        // Main passed line
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('passed_route'),
            points: passedPoints,
            color: const Color(0xFF4DB6AC), // Teal like Google Maps completed
            width: 7,
            patterns: [],
          ),
        );
      }

      // Draw the remaining route (blue - like Google Maps)
      final remainingPoints = _isNavigating && passedIndex > 0
          ? _roadRoutePoints.sublist(passedIndex)
          : _roadRoutePoints;

      if (remainingPoints.length >= 2) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: remainingPoints,
            color: const Color(0xFF4285F4), // Google Blue
            width: 7, // Thicker for better visibility
            patterns: [],
          ),
        );
      }
    } else {
      // Fallback: Draw straight lines between toll plazas
      final straightPoints =
          _routePoints.map((tp) => LatLng(tp.point.lat, tp.point.lon)).toList();
      if (straightPoints.length >= 2) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route_fallback'),
            points: straightPoints,
            color: _primaryBlue.withOpacity(0.7),
            width: 4,
            patterns: [
              PatternItem.dash(20),
              PatternItem.gap(10)
            ], // Dashed to show it's approximate
          ),
        );
      }
    }

    setState(() {});
  }

  /// Filter points to only include toll plazas that are ahead on the route
  /// This prevents backtracking (e.g., going to ISB toll plaza when you're already past it)
  /// Uses the motorway's linear order (distanceFromStart) to determine direction
  List<MotorwayPoint> _filterPointsOnRoute(List<MotorwayPoint> allPoints) {
    if (_currentPosition == null || allPoints.length < 2) return allPoints;

    final userLat = _currentPosition!.latitude;
    final userLon = _currentPosition!.longitude;
    final destination = allPoints.last;
    final routeStart = allPoints.first;

    // Find the nearest point on the motorway to user's current position
    double minDistance = double.infinity;
    int nearestIndex = 0;

    for (int i = 0; i < allPoints.length; i++) {
      final point = allPoints[i];
      final dist = Geolocator.distanceBetween(
        userLat,
        userLon,
        point.lat,
        point.lon,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestIndex = i;
      }
    }

    // Determine travel direction by comparing distanceFromStart values
    // If destination's distanceFromStart > start's distanceFromStart, we're going forward
    final goingForward =
        destination.distanceFromStart > routeStart.distanceFromStart;

    // User's approximate position on the motorway (interpolated distanceFromStart)
    // Use the nearest point's distanceFromStart as reference
    final nearestPoint = allPoints[nearestIndex];
    final userDistanceFromStart = nearestPoint.distanceFromStart;

    // Filter points: only include those ahead of user in travel direction
    final pointsAhead = <MotorwayPoint>[];

    for (final point in allPoints) {
      final isDestination = point.id == destination.id;
      final isAhead = goingForward
          ? point.distanceFromStart >= userDistanceFromStart
          : point.distanceFromStart <= userDistanceFromStart;

      // Also check if point is very close to user (within 5km direct distance)
      // This handles cases where user might be slightly off the motorway
      final distToPoint = Geolocator.distanceBetween(
        userLat,
        userLon,
        point.lat,
        point.lon,
      );
      final isNearby = distToPoint < 5000;

      if (isDestination || isAhead || isNearby) {
        pointsAhead.add(point);
      }
    }

    // If we filtered out too many, just use original
    if (pointsAhead.isEmpty) return allPoints;

    // Ensure correct order based on travel direction
    if (!goingForward) {
      pointsAhead
          .sort((a, b) => b.distanceFromStart.compareTo(a.distanceFromStart));
    } else {
      pointsAhead
          .sort((a, b) => a.distanceFromStart.compareTo(b.distanceFromStart));
    }

    return pointsAhead;
  }

  /// Get current motorway points
  List<MotorwayPoint> get _currentMotorwayPoints =>
      PakistanMotorways.getPoints(_selectedMotorwayId);

  List<MotorwayPoint> _getFilteredPoints(String query) {
    final points = _currentMotorwayPoints;
    if (query.isEmpty) return points;
    return points
        .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_darkBlue, _primaryBlue, _lightBlue],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                _buildAppBar(),
                // Hide search section during navigation for better map visibility
                if (!_isNavigating) _buildSearchSection(),
                // Only show toggle and content after route is confirmed
                if (_routeConfirmed) ...[
                  _buildViewToggle(),
                  Expanded(
                    child: _isLoading
                        ? _buildLoadingView()
                        : _error != null
                            ? _buildErrorView()
                            : _currentView == 0
                                ? _buildTimelineView()
                                : _buildMapView(),
                  ),
                ] else ...[
                  // Show route selection UI before confirming
                  Expanded(child: _buildRouteSelectionView()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Initial view showing route selection before loading data
  Widget _buildRouteSelectionView() {
    final hasDestination = _toId != null;
    final destinationName = hasDestination
        ? _currentMotorwayPoints
            .firstWhere((p) => p.id == _toId,
                orElse: () => _currentMotorwayPoints.last)
            .name
        : null;

    // Calculate route preview (without loading weather)
    final previewPoints = hasDestination
        ? (_fromId == null
            ? PakistanMotorways.getPointsTo(_selectedMotorwayId, _toId!)
            : PakistanMotorways.getPointsBetween(
                _selectedMotorwayId, _fromId!, _toId!))
        : <MotorwayPoint>[];

    final totalDistance = previewPoints.isNotEmpty
        ? previewPoints.last.distanceFromStart -
            previewPoints.first.distanceFromStart
        : 0;
    final estimatedTime =
        (totalDistance / 100 * 60).round(); // Rough estimate at 100km/h

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Route preview card
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _accentBlue.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.navigation,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Plan Your Journey',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    hasDestination
                                        ? 'To $destinationName'
                                        : 'Select your destination above',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Route preview stats
                      if (hasDestination) ...[
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildPreviewStat(Icons.straighten,
                                  '$totalDistance km', 'Distance'),
                              Container(
                                  width: 1, height: 50, color: Colors.white24),
                              _buildPreviewStat(Icons.schedule,
                                  '~${estimatedTime}m', 'Est. Time'),
                              Container(
                                  width: 1, height: 50, color: Colors.white24),
                              _buildPreviewStat(Icons.location_on,
                                  '${previewPoints.length}', 'Stops'),
                            ],
                          ),
                        ),

                        // Preview of stops (scrollable)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: ListView.builder(
                              itemCount: previewPoints.length,
                              itemBuilder: (context, index) {
                                final point = previewPoints[index];
                                final isFirst = index == 0;
                                final isLast =
                                    index == previewPoints.length - 1;

                                return Row(
                                  children: [
                                    // Timeline dot
                                    SizedBox(
                                      width: 30,
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: isLast
                                                  ? Colors.green
                                                  : isFirst
                                                      ? _accentBlue
                                                      : Colors.white54,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          if (!isLast)
                                            Container(
                                              width: 2,
                                              height: 30,
                                              color: Colors.white24,
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Point name
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _getPointIcon(point.type),
                                              color: Colors.white54,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                point.name,
                                                style: TextStyle(
                                                  color: isLast || isFirst
                                                      ? Colors.white
                                                      : Colors.white70,
                                                  fontSize: 13,
                                                  fontWeight: isLast || isFirst
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${point.distanceFromStart} km',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.5),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ] else ...[
                        // No destination selected
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.route,
                                  size: 80,
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Select a destination\nto see route preview',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Start Journey Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: hasDestination ? _confirmRouteAndLoad : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: hasDestination ? Colors.white : Colors.white38,
                foregroundColor: _primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: hasDestination ? 4 : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.navigation,
                    color: hasDestination ? _primaryBlue : Colors.white54,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Start Journey',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: hasDestination ? _primaryBlue : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: _accentBlue, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_routeConfirmed && !_isNavigating) {
                // Go back to route selection
                setState(() {
                  _routeConfirmed = false;
                  _routePoints.clear();
                });
              } else if (_isNavigating) {
                // Stop navigation first
                _stopNavigation();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isNavigating ? 'Navigating' : 'M2 Motorway',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _isNavigating ? 'Following your route' : 'Islamabad ↔ Lahore',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_routeConfirmed && !_isNavigating)
            IconButton(
              icon: const Icon(Icons.play_circle_outline, color: Colors.white),
              tooltip: 'Start Navigation',
              onPressed: _startNavigation,
            ),
          if (_isNavigating)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              tooltip: 'Stop Navigation',
              onPressed: _stopNavigation,
            ),
          if (_routeConfirmed)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadRoute,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Motorway Selector
                _buildMotorwaySelector(),
                const SizedBox(height: 12),
                // From field
                _buildSearchField(
                  label: 'From',
                  value: _fromId == null
                      ? 'Current Location'
                      : _currentMotorwayPoints
                          .firstWhere((p) => p.id == _fromId,
                              orElse: () => _currentMotorwayPoints.first)
                          .name,
                  icon: Icons.my_location,
                  isActive: _showFromSearch,
                  controller: _fromSearchController,
                  onTap: () {
                    setState(() {
                      _showFromSearch = !_showFromSearch;
                      _showToSearch = false;
                    });
                  },
                ),
                if (_showFromSearch) _buildSearchDropdown(isFrom: true),
                const SizedBox(height: 12),
                // To field
                _buildSearchField(
                  label: 'To',
                  value: _toId == null
                      ? 'Select Destination'
                      : _currentMotorwayPoints
                          .firstWhere((p) => p.id == _toId,
                              orElse: () => _currentMotorwayPoints.last)
                          .name,
                  icon: Icons.location_on,
                  isActive: _showToSearch,
                  controller: _toSearchController,
                  onTap: () {
                    setState(() {
                      _showToSearch = !_showToSearch;
                      _showFromSearch = false;
                    });
                  },
                ),
                if (_showToSearch) _buildSearchDropdown(isFrom: false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMotorwaySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedMotorwayId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          dropdownColor: _darkBlue,
          style: const TextStyle(color: Colors.white),
          items: PakistanMotorways.motorways.map((motorway) {
            return DropdownMenuItem<String>(
              value: motorway.id,
              child: Row(
                children: [
                  Icon(
                    Icons.directions_car,
                    color: motorway.id == _selectedMotorwayId
                        ? Colors.amber
                        : Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          motorway.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${motorway.subtitle} • ${motorway.distanceKm} km',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null && value != _selectedMotorwayId) {
              setState(() {
                _selectedMotorwayId = value;
                // Reset selections when motorway changes
                _fromId = null;
                _toId = null;
                _routePoints = [];
                _roadRoutePoints = [];
                _routeConfirmed = false;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required String label,
    required String value,
    required IconData icon,
    required bool isActive,
    required TextEditingController controller,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? _accentBlue : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isActive ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchDropdown({required bool isFrom}) {
    final controller = isFrom ? _fromSearchController : _toSearchController;
    final filteredPoints = _getFilteredPoints(controller.text);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search input
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search toll plaza...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                border: InputBorder.none,
                prefixIcon:
                    Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Options list
          Expanded(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (isFrom)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.my_location,
                        color: _accentBlue, size: 20),
                    title: const Text(
                      'Current Location',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      setState(() {
                        _fromId = null;
                        _showFromSearch = false;
                        controller.clear();
                      });
                      _loadRoute();
                    },
                  ),
                ...filteredPoints.map((point) => ListTile(
                      dense: true,
                      leading: Icon(
                        _getPointIcon(point.type),
                        color: Colors.white.withOpacity(0.8),
                        size: 20,
                      ),
                      title: Text(
                        point.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${point.distanceFromStart} km from ISB',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          if (isFrom) {
                            _fromId = point.id;
                            _showFromSearch = false;
                          } else {
                            _toId = point.id;
                            _showToSearch = false;
                          }
                          controller.clear();
                        });
                        _loadRoute();
                      },
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPointIcon(PointType type) {
    switch (type) {
      case PointType.tollPlaza:
        return Icons.money;
      case PointType.interchange:
        return Icons.swap_horiz;
      case PointType.serviceArea:
        return Icons.local_gas_station;
      case PointType.destination:
        return Icons.flag;
    }
  }

  Widget _buildViewToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton(
              label: 'Timeline',
              icon: Icons.view_timeline,
              isActive: _currentView == 0,
              onTap: () => setState(() => _currentView = 0),
            ),
          ),
          Expanded(
            child: _buildSegmentButton(
              label: 'Map',
              icon: Icons.map_outlined,
              isActive: _currentView == 1,
              onTap: () => setState(() => _currentView = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? _primaryBlue : Colors.white.withOpacity(0.8),
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? _primaryBlue : Colors.white.withOpacity(0.9),
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Loading text
          Center(
            child: Text(
              'Loading timeline weather data...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Skeleton cards
          ...List.generate(5, (index) => _buildSkeletonCard()),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon placeholder
              _buildShimmerBox(width: 48, height: 48, isCircle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title placeholder
                    _buildShimmerBox(width: 140, height: 16),
                    const SizedBox(height: 8),
                    // Subtitle placeholder
                    _buildShimmerBox(width: 100, height: 12),
                  ],
                ),
              ),
              // Temperature placeholder
              _buildShimmerBox(width: 50, height: 24),
            ],
          ),
          const SizedBox(height: 16),
          // Details row placeholders
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildShimmerBox(width: 70, height: 12),
              _buildShimmerBox(width: 70, height: 12),
              _buildShimmerBox(width: 70, height: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    bool isCircle = false,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 0.6),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 0.3),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
          builder: (context, value2, child) {
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(value),
                borderRadius:
                    isCircle ? null : BorderRadius.circular(height / 2),
                shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              color: Colors.white.withOpacity(0.7), size: 48),
          const SizedBox(height: 16),
          Text(
            _error ?? 'An error occurred',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadRoute,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    // Filter out passed toll plazas during navigation
    final visiblePoints = _isNavigating
        ? _routePoints.skip(_currentPointIndex).toList()
        : _routePoints;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: visiblePoints.length + 1, // +1 for current location card
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildCurrentLocationCard();
        }
        final tp = visiblePoints[index - 1];
        final isLast = index == visiblePoints.length;
        return _buildTimelineCard(tp, isLast);
      },
    );
  }

  Widget _buildCurrentLocationCard() {
    final hasMetar = _currentLocationMetar != null;
    final weather = _currentLocationWeather;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _accentBlue.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Location',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isNavigating ? 'Navigating...' : 'Starting Point',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Speed display during navigation
                    if (_isNavigating) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _currentSpeed > 100
                                  ? Colors.red.shade400
                                  : Colors.green.shade400,
                              _currentSpeed > 100
                                  ? Colors.red.shade600
                                  : Colors.green.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: (_currentSpeed > 100
                                      ? Colors.red
                                      : Colors.green)
                                  .withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              '${_currentSpeed.round()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              ' km/h',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (hasMetar)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.airplanemode_active,
                                color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'METAR',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildWeatherGrid(
                  metar: _currentLocationMetar,
                  weather: weather,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineCard(TravelPoint tp, bool isLast) {
    final metar = _metarData[tp.point.id];
    final hasMetar = metar != null;
    final isServiceArea = tp.point.type == PointType.serviceArea;
    final isDestination = tp.point.type == PointType.destination;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline line with animated dot
        SizedBox(
          width: 44,
          child: Column(
            children: [
              Container(
                width: isDestination ? 22 : 18,
                height: isDestination ? 22 : 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDestination
                        ? [Colors.green.shade300, Colors.green.shade600]
                        : isServiceArea
                            ? [Colors.orange.shade300, Colors.orange.shade600]
                            : [
                                _getPointColor(tp.point.type),
                                _getPointColor(tp.point.type).withOpacity(0.7)
                              ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: _getPointColor(tp.point.type).withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: isDestination
                    ? const Icon(Icons.flag, color: Colors.white, size: 12)
                    : isServiceArea
                        ? const Icon(Icons.local_gas_station,
                            color: Colors.white, size: 10)
                        : null,
              ),
              if (!isLast)
                Container(
                  width: 3,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.5),
                        Colors.white.withOpacity(0.2),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
        // Card with improved design
        Expanded(
          child: GestureDetector(
            onTap: () => _showPointDetails(tp),
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 20 : 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDestination
                            ? [
                                Colors.green.withOpacity(0.25),
                                Colors.green.withOpacity(0.1)
                              ]
                            : isServiceArea
                                ? [
                                    Colors.orange.withOpacity(0.2),
                                    Colors.orange.withOpacity(0.08)
                                  ]
                                : [
                                    Colors.white.withOpacity(0.18),
                                    Colors.white.withOpacity(0.08)
                                  ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDestination
                            ? Colors.green.withOpacity(0.4)
                            : isServiceArea
                                ? Colors.orange.withOpacity(0.3)
                                : Colors.white.withOpacity(0.25),
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row with type badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _getPointColor(tp.point.type)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _getPointIcon(tp.point.type),
                                color: _getPointColor(tp.point.type),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tp.point.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.straighten,
                                          size: 12, color: Colors.white54),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${tp.point.distanceFromStart} km',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (tp.etaFromStart != null) ...[
                                        const SizedBox(width: 10),
                                        Icon(Icons.schedule,
                                            size: 12, color: Colors.white54),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDuration(tp.etaFromStart!),
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.7),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // METAR badge + tap hint
                            Column(
                              children: [
                                if (hasMetar)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.flight,
                                            color: Colors.white, size: 11),
                                        SizedBox(width: 3),
                                        Text('METAR',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Icon(Icons.touch_app,
                                    size: 16, color: Colors.white38),
                              ],
                            ),
                          ],
                        ),

                        // Facilities badge (if service area)
                        if (tp.point.facilities != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_cafe,
                                    size: 14, color: Colors.orange.shade200),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    tp.point.facilities!,
                                    style: TextStyle(
                                      color: Colors.orange.shade100,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),
                        // Weather data with improved chips
                        _buildCompactWeatherRow(
                            metar: metar, weather: tp.weather),

                        // Prayer times row - shows which namaz will be active at arrival
                        if (tp.nextPrayer != null &&
                            tp.nextPrayerTime != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.purple.withOpacity(0.2),
                                  Colors.indigo.withOpacity(0.15),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.purple.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mosque,
                                    size: 14, color: Colors.purple.shade200),
                                const SizedBox(width: 6),
                                Text(
                                  '${tp.nextPrayer}',
                                  style: TextStyle(
                                    color: Colors.purple.shade100,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (tp.etaFromStart != null &&
                                    tp.etaFromStart!.inMinutes > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'at arrival',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactWeatherRow({
    Map<String, dynamic>? metar,
    TravelWeather? weather,
  }) {
    if (metar != null) {
      // Show METAR data: icon, condition, visibility, temp, humidity, wind
      return Row(
        children: [
          _buildWeatherChip(
            Icons.thermostat,
            '${metar['temp_c']}°',
          ),
          _buildWeatherChip(
            Icons.water_drop,
            '${metar['humidity']}%',
          ),
          _buildWeatherChip(
            Icons.air,
            '${metar['wind_kph']} km/h',
          ),
          _buildWeatherChip(
            Icons.visibility,
            '${metar['visibility_km']} km',
          ),
        ],
      );
    } else if (weather != null) {
      // Show weather data: temp, humidity, wind, feels like
      return Row(
        children: [
          _buildWeatherChip(
            Icons.thermostat,
            '${weather.tempC.round()}°',
          ),
          _buildWeatherChip(
            Icons.water_drop,
            '${weather.humidity}%',
          ),
          _buildWeatherChip(
            Icons.air,
            '${weather.windKph.round()} km/h',
          ),
        ],
      );
    }

    // Show loading/no data placeholder
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_queue, size: 14, color: Colors.white38),
              const SizedBox(width: 6),
              Text(
                'Loading weather...',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeatherChip(IconData icon, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherGrid({
    Map<String, dynamic>? metar,
    Map<String, dynamic>? weather,
  }) {
    if (metar != null) {
      // METAR data grid
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _buildWeatherGridItem(
              Icons.thermostat, 'Temp', '${metar['temp_c']}°C'),
          _buildWeatherGridItem(
              Icons.water_drop, 'Humidity', '${metar['humidity']}%'),
          _buildWeatherGridItem(Icons.air, 'Wind', '${metar['wind_kph']} km/h'),
          _buildWeatherGridItem(
              Icons.visibility, 'Visibility', '${metar['visibility_km']} km'),
          if (metar['condition_text'] != '--')
            _buildWeatherGridItem(
                Icons.cloud, 'Condition', metar['condition_text']),
        ],
      );
    } else if (weather != null) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _buildWeatherGridItem(Icons.thermostat, 'Temp',
              '${weather['temp_c']?.toStringAsFixed(1) ?? '--'}°C'),
          _buildWeatherGridItem(
              Icons.water_drop, 'Humidity', '${weather['humidity'] ?? '--'}%'),
          _buildWeatherGridItem(Icons.air, 'Wind',
              '${weather['wind_kph']?.toStringAsFixed(0) ?? '--'} km/h'),
        ],
      );
    }

    return const Text(
      'Weather data unavailable',
      style: TextStyle(color: Colors.white54),
    );
  }

  Widget _buildWeatherGridItem(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 10,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getPointColor(PointType type) {
    switch (type) {
      case PointType.tollPlaza:
        return Colors.red.shade300;
      case PointType.interchange:
        return Colors.blue.shade300;
      case PointType.serviceArea:
        return Colors.orange.shade300;
      case PointType.destination:
        return Colors.green.shade300;
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  void _showPointDetails(TravelPoint tp) {
    final metar = _metarData[tp.point.id];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_primaryBlue.withOpacity(0.95), _darkBlue],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Header
            Row(
              children: [
                Icon(
                  _getPointIcon(tp.point.type),
                  color: _getPointColor(tp.point.type),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tp.point.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${tp.point.distanceFromStart} km from Islamabad',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (metar != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.airplanemode_active,
                            color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('METAR', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
              ],
            ),
            if (tp.point.facilities != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_gas_station,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tp.point.facilities!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            // ETA info
            if (tp.etaFromStart != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estimated Time of Arrival',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _formatDuration(tp.etaFromStart!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (tp.estimatedArrival != null)
                      Text(
                        '${tp.estimatedArrival!.hour.toString().padLeft(2, '0')}:${tp.estimatedArrival!.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Weather details
            const Text(
              'Weather',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildWeatherGrid(
              metar: metar,
              weather: tp.weather != null
                  ? {
                      'temp_c': tp.weather!.tempC,
                      'humidity': tp.weather!.humidity,
                      'wind_kph': tp.weather!.windKph,
                    }
                  : null,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    if (_routePoints.isEmpty) {
      return const Center(
        child: Text(
          'Select a route to view on map',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final centerLat = _routePoints.isNotEmpty
        ? _routePoints.map((p) => p.point.lat).reduce((a, b) => a + b) /
            _routePoints.length
        : 32.0;
    final centerLon = _routePoints.isNotEmpty
        ? _routePoints.map((p) => p.point.lon).reduce((a, b) => a + b) /
            _routePoints.length
        : 73.0;

    return Stack(
      children: [
        // Map
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(centerLat, centerLon),
              zoom: 7,
            ),
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _mapController = controller;
              // Fit bounds to show entire route
              if (_routePoints.isNotEmpty) {
                final bounds = LatLngBounds(
                  southwest: LatLng(
                    _routePoints
                        .map((p) => p.point.lat)
                        .reduce((a, b) => a < b ? a : b),
                    _routePoints
                        .map((p) => p.point.lon)
                        .reduce((a, b) => a < b ? a : b),
                  ),
                  northeast: LatLng(
                    _routePoints
                        .map((p) => p.point.lat)
                        .reduce((a, b) => a > b ? a : b),
                    _routePoints
                        .map((p) => p.point.lon)
                        .reduce((a, b) => a > b ? a : b),
                  ),
                );
                controller
                    .animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
              }
            },
            mapType: MapType.normal,
            zoomControlsEnabled: false,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            onCameraMove: (_) {
              // User is manually moving the map, stop following
              if (_isNavigating && _isFollowingUser) {
                setState(() => _isFollowingUser = false);
              }
            },
          ),
        ),

        // Weather Card Overlay - Top Left (always visible)
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: _buildMapWeatherCard(),
        ),

        // Turn-by-turn Navigation Instructions - Below weather card (shown only during navigation)
        if (_isNavigating &&
            _navigationSteps.isNotEmpty &&
            _currentStepIndex < _navigationSteps.length)
          Positioned(
            top: 130, // Below weather card
            left: 16,
            right: 16,
            child: _buildNavigationInstructionCard(),
          ),

        // Route Info Card - Bottom (always visible)
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: _buildRouteInfoCard(),
        ),

        // Location/Recenter Button - Bottom Right
        Positioned(
          bottom: 100,
          right: 16,
          child: _buildMapButton(
            // Show different icon based on state:
            // - Not navigating: my_location (current location)
            // - Navigating + following: navigation (compass mode active)
            // - Navigating + not following: gps_fixed (recenter)
            icon: !_isNavigating
                ? Icons.my_location
                : (_isFollowingUser ? Icons.navigation : Icons.gps_fixed),
            onTap: () {
              if (_currentPosition != null) {
                if (_isNavigating) {
                  // Re-enable following and move to current location with road bearing
                  setState(() => _isFollowingUser = true);
                  final bearing =
                      _roadBearing != 0 ? _roadBearing : _currentHeading;
                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: LatLng(_currentPosition!.latitude,
                            _currentPosition!.longitude),
                        zoom: 18, // Closer zoom like Google Maps
                        bearing: bearing, // Use road bearing
                        tilt: 60, // More tilt for 3D effect
                      ),
                    ),
                  );
                } else {
                  // Not navigating, just move to current location
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(
                      LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                    ),
                  );
                }
              }
            },
          ),
        ),

        // Zoom Controls - Bottom Right
        Positioned(
          bottom: 160,
          right: 16,
          child: Column(
            children: [
              _buildMapButton(
                icon: Icons.add,
                onTap: () =>
                    _mapController?.animateCamera(CameraUpdate.zoomIn()),
              ),
              const SizedBox(height: 8),
              _buildMapButton(
                icon: Icons.remove,
                onTap: () =>
                    _mapController?.animateCamera(CameraUpdate.zoomOut()),
              ),
            ],
          ),
        ),

        // Navigation Icon Toggle - Bottom Right (only during navigation)
        if (_isNavigating)
          Positioned(
            bottom: 260,
            right: 16,
            child: _buildMapButton(
              icon: _useCarIcon ? Icons.directions_car : Icons.navigation,
              onTap: () {
                setState(() {
                  _useCarIcon = !_useCarIcon;
                });
                _updateMapMarkers();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMapButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: _primaryBlue, size: 24),
      ),
    );
  }

  Widget _buildMapWeatherCard() {
    final hasMetar = _currentLocationMetar != null;
    final metar = _currentLocationMetar;
    final weather = _currentLocationWeather;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Weather Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_lightBlue, _primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  hasMetar ? Icons.flight : Icons.wb_sunny,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),

              // Weather Data
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          hasMetar
                              ? '${metar?['temp_c'] ?? '--'}°C'
                              : '${weather?['temp_c']?.toStringAsFixed(0) ?? '--'}°C',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _darkBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasMetar)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.flight,
                                    size: 10, color: Colors.green.shade700),
                                const SizedBox(width: 2),
                                Text(
                                  'METAR',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasMetar
                          ? (metar?['condition_text'] ?? 'Current Weather')
                          : (weather?['condition'] ?? 'Current Weather'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Additional Stats
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMapWeatherStat(
                    Icons.water_drop,
                    hasMetar
                        ? '${metar?['humidity'] ?? '--'}%'
                        : '${weather?['humidity'] ?? '--'}%',
                  ),
                  const SizedBox(height: 6),
                  _buildMapWeatherStat(
                    Icons.air,
                    hasMetar
                        ? '${metar?['wind_kph'] ?? '--'} km/h'
                        : '${weather?['wind_kph']?.toStringAsFixed(0) ?? '--'} km/h',
                  ),
                  if (hasMetar) ...[
                    const SizedBox(height: 6),
                    _buildMapWeatherStat(
                      Icons.visibility,
                      '${metar?['visibility_km'] ?? '--'} km',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapWeatherStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _primaryBlue),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  /// Build navigation instruction card with turn-by-turn directions
  Widget _buildNavigationInstructionCard() {
    if (_currentStepIndex >= _navigationSteps.length) {
      return const SizedBox.shrink();
    }

    final currentStep = _navigationSteps[_currentStepIndex];
    final nextStep = _currentStepIndex + 1 < _navigationSteps.length
        ? _navigationSteps[_currentStepIndex + 1]
        : null;

    // Calculate distance to next turn
    double distanceToTurn = 0;
    if (_currentPosition != null) {
      distanceToTurn = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        currentStep.endLocation.latitude,
        currentStep.endLocation.longitude,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.indigo.withOpacity(0.85),
                Colors.blue.shade800.withOpacity(0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Current instruction
              Row(
                children: [
                  // Maneuver icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        currentStep.maneuverIcon,
                        style:
                            const TextStyle(fontSize: 28, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Instruction text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentStep.cleanInstruction,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.straighten,
                                size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              distanceToTurn < 1000
                                  ? '${distanceToTurn.round()} m'
                                  : '${(distanceToTurn / 1000).toStringAsFixed(1)} km',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Speed indicator
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _currentSpeed > 100
                          ? Colors.red.withOpacity(0.3)
                          : Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${_currentSpeed.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'km/h',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Next instruction preview
              if (nextStep != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        nextStep.maneuverIcon,
                        style: const TextStyle(
                            fontSize: 16, color: Colors.white60),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Then: ${nextStep.cleanInstruction}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteInfoCard() {
    final startPoint = _fromId == null
        ? 'Current Location'
        : _currentMotorwayPoints
            .firstWhere((p) => p.id == _fromId,
                orElse: () => _currentMotorwayPoints.first)
            .name;
    final endPoint = _toId == null
        ? 'Destination'
        : _currentMotorwayPoints
            .firstWhere((p) => p.id == _toId,
                orElse: () => _currentMotorwayPoints.last)
            .name;

    // Calculate total distance and ETA
    final totalDistance = _routePoints.isNotEmpty
        ? _routePoints.last.point.distanceFromStart -
            (_routePoints.isNotEmpty
                ? _routePoints.first.point.distanceFromStart
                : 0)
        : 0;
    final totalEta =
        _routePoints.isNotEmpty && _routePoints.last.etaFromStart != null
            ? _formatDuration(_routePoints.last.etaFromStart!)
            : '--';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _darkBlue.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Route points row
              Row(
                children: [
                  // From
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _accentBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            startPoint,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.arrow_forward,
                        color: Colors.white54, size: 18),
                  ),
                  // To
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.green.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            endPoint,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildRouteInfoStat(
                      Icons.route, '$totalDistance km', 'Distance'),
                  Container(width: 1, height: 30, color: Colors.white24),
                  _buildRouteInfoStat(Icons.access_time, totalEta, 'ETA'),
                  Container(width: 1, height: 30, color: Colors.white24),
                  _buildRouteInfoStat(
                      Icons.location_on, '${_routePoints.length}', 'Stops'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteInfoStat(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _accentBlue, size: 16),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
