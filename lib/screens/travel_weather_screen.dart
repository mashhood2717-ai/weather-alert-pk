// lib/screens/travel_weather_screen.dart

import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/motorway_point.dart';
import '../services/travel_weather_service.dart';
import '../services/prayer_service.dart';
import '../services/notification_service.dart';
import '../metar_service.dart';
import '../services/weather_controller.dart';
import '../utils/icon_mapper.dart';

class TravelWeatherScreen extends StatefulWidget {
  final bool isDay;

  const TravelWeatherScreen({super.key, this.isDay = true});

  @override
  State<TravelWeatherScreen> createState() => _TravelWeatherScreenState();
}

class _TravelWeatherScreenState extends State<TravelWeatherScreen>
    with TickerProviderStateMixin {
  // View toggle: 0 = Map, 1 = Timeline
  int _currentView = 0;

  // Navigation state
  bool _routeConfirmed = false; // NEW: Only load data after user confirms route
  bool _isNavigating = false; // NEW: Real-time navigation mode
  double _currentSpeed = 0.0; // Current speed in km/h

  // Departure time selection
  DateTime? _departureTime; // null means "Now"

  // Timeline slider state
  bool _showTimelineSlider = false;
  double _sliderValue = 0.0; // 0.0 to 1.0 representing position along route
  int _sliderPointIndex = 0; // Current point index based on slider
  bool _isSliderPlaying = false; // Auto-play slider
  Timer? _sliderPlayTimer; // Timer for auto-play

  // Theme mode - null means follow system, true/false means user override
  bool? _userThemeOverride;
  bool _isDarkMode = true; // Will be set from system in didChangeDependencies

  // Map layer selection
  String _selectedMapLayer =
      'temp'; // 'temp', 'humidity', 'visibility', 'wind', 'uv'
  bool _showLayerPicker = false;

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
  final Map<String, Map<String, dynamic>?> _metarData = {};

  // Map controller
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // Real road route from Google Directions API
  List<LatLng> _roadRoutePoints = [];
  int _routeDistanceMeters = 0;
  int _routeDurationSeconds = 0;
  List<NavigationStep> _navigationSteps = []; // Turn-by-turn instructions
  int _currentStepIndex = 0; // Current navigation step
  double _firstPointDistFromStart =
      0; // Reference value for distance calculations

  // Real-time navigation tracking
  StreamSubscription<Position>? _positionStream;
  int _currentPointIndex = 0; // Track which point user has passed
  int _confirmedPointIndex = 0; // Committed index (prevents flip-flop)
  int _highestAchievedIndex =
      0; // NEVER go below this - prevents screen-off regression
  DateTime? _lastPointChangeTime; // Debounce for point changes
  // ignore: unused_field
  static const int _pointChangeDebounceMs =
      3000; // 3 second debounce (reserved for future use)
  bool _useCarIcon = false; // false = arrow (like Google Maps), true = car icon
  double _currentHeading =
      0; // Direction user is facing (from GPS or calculated)
  double _roadBearing =
      0; // Bearing calculated from road polyline (more accurate)
  bool _isFollowingUser = true; // Whether map is auto-following user location
  bool _isProgrammaticCameraMove =
      false; // Flag to distinguish programmatic vs user camera moves
  int _closestPolylineIndex = 0; // Index of closest point on polyline

  // Destination arrival tracking
  bool _hasArrived = false; // True when user reaches destination
  bool _arrivedDialogShown = false; // Prevent showing dialog multiple times

  // Current prayer tracking (for countdown display)
  String? _currentPrayerName;
  DateTime?
      _currentPrayerEndsAt; // When current prayer ends (next prayer starts)
  Timer? _prayerCountdownTimer;

  // Off-route detection and auto-rerouting
  bool _isOffRoute = false;
  static const double _offRouteThresholdMeters =
      150; // 150m threshold for off-route (increased for GPS accuracy)

  // Ultra-smooth 60fps map animation with continuous motion
  Ticker? _mapTicker;
  double _targetLat = 0;
  double _targetLon = 0;
  double _targetBearing = 0;
  double _displayLat = 0;
  double _displayLon = 0;
  double _displayBearing = 0;
  DateTime? _lastTickTime;

  // Continuous motion - keeps moving forward based on speed
  double _motionSpeedMps = 0; // Current speed in meters per second
  double _motionBearingRad = 0; // Current bearing in radians

  // Smoothing for motion (low-pass filter)
  double _smoothMotionSpeed = 0;
  double _smoothMotionBearing = 0;

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Dark theme colors (Apple Weather style - night mode)
  static const Color _primaryBlueDark = Color(0xFF1565C0);
  static const Color _lightBlueDark = Color(0xFF42A5F5);
  static const Color _darkBlueDark = Color(0xFF0D47A1);
  static const Color _accentBlueDark = Color(0xFF64B5F6);
  static const Color _bgDarkColor = Color(0xFF1C1C1E);
  static const Color _cardDarkColor = Color(0xFF2C2C2E);

  // Light theme colors - Daytime blue sky (white text still works on blue)
  static const Color _primaryBlueLight = Color(0xFF1976D2);
  static const Color _lightBlueLight = Color(0xFF42A5F5);
  static const Color _darkBlueLight = Color(0xFF1565C0);
  static const Color _accentBlueLight = Color(0xFF64B5F6);
  static const Color _bgLightColor = Color(0xFF2196F3); // Bright blue sky
  static const Color _cardLightColor = Color(0xFF1565C0); // Darker blue cards

  static const Color _orangeAccent = Color(0xFFFF9500);

  // Dynamic theme getters - both themes use white text (works on dark/blue backgrounds)
  Color get _primaryBlue => _isDarkMode ? _primaryBlueDark : _primaryBlueLight;
  Color get _lightBlue => _isDarkMode ? _lightBlueDark : _lightBlueLight;
  Color get _darkBlue => _isDarkMode ? _darkBlueDark : _darkBlueLight;
  Color get _accentBlue => _isDarkMode ? _accentBlueDark : _accentBlueLight;
  Color get _bgDark => _isDarkMode ? _bgDarkColor : _bgLightColor;
  Color get _cardDark => _isDarkMode ? _cardDarkColor : _cardLightColor;
  Color get _textColor =>
      Colors.white; // White text works on both dark and blue
  Color get _textSecondary => Colors.white70;
  Color get _borderColor =>
      Colors.white.withValues(alpha: _isDarkMode ? 0.1 : 0.2);
  // ignore: unused_element
  Color get _iconColor => Colors.white; // Reserved for future use

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

    // Create custom marker icons
    _createCustomMarkerIcons();

    // Just get current location, don't load route yet
    _initializeLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set theme from system if user hasn't manually overridden
    if (_userThemeOverride == null) {
      final brightness = MediaQuery.of(context).platformBrightness;
      _isDarkMode = brightness == Brightness.dark;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _mapTicker?.dispose();
    _fromSearchController.dispose();
    _toSearchController.dispose();
    _mapController?.dispose();
    _positionStream?.cancel(); // Cancel location tracking
    _sliderPlayTimer?.cancel(); // Cancel slider auto-play

    // Cancel navigation notification when leaving screen
    if (_isNavigating) {
      NotificationService().cancelNavigationNotification();
    }

    super.dispose();
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoading = true);

    try {
      // First try last known position (instant, no GPS wait)
      Position? lastKnown;
      try {
        lastKnown = await Geolocator.getLastKnownPosition();
      } catch (_) {}

      if (lastKnown != null && mounted) {
        setState(() {
          _currentPosition = lastKnown;
          _isLoading = false; // Show UI immediately with last known
        });
      }

      // Then get fresh position in background (only if needed)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, // Use low for faster response
        timeLimit: const Duration(seconds: 5), // Don't wait too long
      );
      if (mounted) {
        setState(() => _currentPosition = position);
      }
      // DON'T load route here - wait for user to confirm destination
    } catch (e) {
      // If we have last known, don't show error
      if (_currentPosition == null && mounted) {
        setState(() => _error = 'Failed to get location: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

    // Ensure we have current position before fetching weather
    if (_currentPosition == null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        if (mounted) {
          setState(() => _currentPosition = position);
        }
      } catch (e) {
        debugPrint('Error getting position: $e');
        // Show warning that distances may be inaccurate
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Could not get GPS location. Distances may be inaccurate.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }

    // Fetch current location weather
    await _fetchCurrentLocationWeather();

    // Load route data
    await _loadRoute();
  }

  /// Start real-time navigation tracking
  void _startNavigation() {
    if (_isNavigating) return;

    // DON'T recalculate distances here - they're already correct from initial load
    // Just set the throttle timestamp to prevent immediate recalculation
    _lastDistanceUpdate = DateTime.now();

    setState(() {
      _isNavigating = true;
      _isFollowingUser = true; // Start following user when navigation begins
      _isOffRoute = false;
      _hasArrived = false; // Reset arrival state
      _arrivedDialogShown = false;
    });
    _currentPointIndex = 0;
    _confirmedPointIndex = 0; // Reset confirmed index
    _highestAchievedIndex = 0; // Reset highest achieved - new journey
    _lastPointChangeTime =
        DateTime.now(); // Set to NOW - enables grace period on start
    _currentStepIndex = 0;

    // Initialize smoothed values to current position/heading immediately
    if (_currentPosition != null) {
      _smoothedLat = _currentPosition!.latitude;
      _smoothedLon = _currentPosition!.longitude;
      _smoothedBearing = _roadBearing != 0 ? _roadBearing : _currentHeading;

      // Initialize display position for smooth animation
      _displayLat = _smoothedLat;
      _displayLon = _smoothedLon;
      _displayBearing = _smoothedBearing;
      _targetLat = _smoothedLat;
      _targetLon = _smoothedLon;
      _targetBearing = _smoothedBearing;

      // Initialize motion parameters for continuous movement
      _motionSpeedMps = 0;
      _motionBearingRad = _smoothedBearing * (3.14159 / 180);
      _smoothMotionSpeed = 0;
      _smoothMotionBearing = _motionBearingRad;
    }

    // Start 60fps smooth map animation ticker
    _startMapTicker();

    // Immediately recenter map on current location with navigation view
    if (_currentPosition != null && _mapController != null && mounted) {
      final bearing = _roadBearing != 0 ? _roadBearing : _currentHeading;
      _isProgrammaticCameraMove =
          true; // Prevent onCameraMove from disabling follow
      try {
        _mapController!
            .animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(
                  _currentPosition!.latitude, _currentPosition!.longitude),
              zoom: 18, // Close zoom for navigation
              bearing: bearing,
              tilt: 60, // 3D tilt for immersive navigation
            ),
          ),
        )
            .then((_) {
          if (mounted) _isProgrammaticCameraMove = false;
        });
      } catch (e) {
        debugPrint('⚠️ Map animation error: $e');
        _isProgrammaticCameraMove = false;
      }
    }

    // Update markers to show navigation mode
    _updateMapMarkers();

    // Show navigation notification (like Google Maps)
    _showNavigationNotification();

    // Start prayer countdown timer
    _startPrayerCountdown();

    // Start listening to location updates - ULTRA REAL-TIME
    // Force updates every 100ms for smooth navigation
    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration:
            const Duration(milliseconds: 100), // Force 10 updates/sec
        forceLocationManager: false,
      ),
    ).listen(_onLocationUpdate);
  }

  /// Stop navigation
  void _stopNavigation() {
    _positionStream?.cancel();
    _positionStream = null;

    // Stop smooth map animation
    _mapTicker?.dispose();
    _mapTicker = null;

    // Stop prayer countdown
    _stopPrayerCountdown();

    // Cancel navigation notification
    NotificationService().cancelNavigationNotification();

    setState(() {
      _isNavigating = false;
      _isFollowingUser = true; // Reset for next navigation
    });
  }

  /// Show/update navigation notification
  void _showNavigationNotification() {
    if (!_isNavigating) return;

    String instruction = 'Head to destination';
    String distance = '';
    String? roadName;
    int? remainingMinutes;

    // Get current navigation step
    if (_navigationSteps.isNotEmpty &&
        _currentStepIndex < _navigationSteps.length) {
      final step = _navigationSteps[_currentStepIndex];
      instruction =
          step.cleanInstruction; // Use clean instruction (HTML removed)
      // Format distance from meters
      if (step.distanceMeters >= 1000) {
        distance = '${(step.distanceMeters / 1000).toStringAsFixed(1)} km';
      } else {
        distance = '${step.distanceMeters} m';
      }
      roadName = step.roadName;
    }

    // Calculate remaining time
    if (_routeDurationSeconds > 0) {
      remainingMinutes = (_routeDurationSeconds / 60).round();
    }

    // Calculate remaining distance
    if (_routeDistanceMeters > 0) {
      if (_routeDistanceMeters >= 1000) {
        distance = '${(_routeDistanceMeters / 1000).toStringAsFixed(1)} km';
      } else {
        distance = '$_routeDistanceMeters m';
      }
    }

    NotificationService().showNavigationNotification(
      instruction: instruction,
      distance: distance,
      roadName: roadName,
      remainingMinutes: remainingMinutes,
    );
  }

  // Smoothed values for animation
  double _smoothedLat = 0;
  double _smoothedLon = 0;
  double _smoothedBearing = 0;
  // ignore: unused_field
  DateTime? _lastLocationUpdate;
  // ignore: unused_field
  DateTime? _lastDistanceUpdate;

  /// Recenter on user location
  /// [resetHeading] - if true, also resets the camera bearing to heading direction (like Google Maps double-tap)
  void _recenterOnUser(bool resetHeading) {
    if (_currentPosition == null) return;

    setState(() => _isFollowingUser = true);

    if (_isNavigating) {
      // Use ACTUAL current position - not smoothed, not offset
      // This ensures the cursor is visible and centered
      final lat = _currentPosition!.latitude;
      final lon = _currentPosition!.longitude;

      // For double-tap, use current heading/road bearing
      // For single-tap, keep current camera bearing unless we're recalculating
      double bearing = _smoothedBearing;
      if (resetHeading) {
        bearing = _roadBearing != 0 ? _roadBearing : _currentHeading;
      }

      _isProgrammaticCameraMove =
          true; // Prevent onCameraMove from disabling follow
      _mapController
          ?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lon),
            zoom: 18,
            bearing: bearing,
            tilt: 60,
          ),
        ),
      )
          .then((_) {
        _isProgrammaticCameraMove = false;
      });
    } else {
      // Not navigating, just move to current location (no tilt/bearing)
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
      );
    }
  }

  /// Handle location updates during navigation - SMOOTH like Google Maps
  void _onLocationUpdate(Position position) {
    if (!mounted) return;

    final now = DateTime.now();
    _currentPosition = position;

    // INSTANT SPEED - no lag for speedometer
    final newSpeed = (position.speed * 3.6).clamp(0.0, 300.0);
    _currentSpeed = newSpeed; // Instant update, no smoothing

    // SMOOTH HEADING - interpolate to avoid jumps
    if (position.heading >= 0 && position.speed > 0.3) {
      // Smooth bearing transition (handle 360/0 wraparound)
      double targetBearing = position.heading;
      double diff = targetBearing - _currentHeading;

      // Handle wraparound (e.g., 350 to 10 should go through 0, not back through 180)
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;

      _currentHeading = (_currentHeading + diff * 0.4) % 360;
      if (_currentHeading < 0) _currentHeading += 360;
    }

    // Calculate road bearing from polyline
    final distanceFromRoute = _calculateRoadBearing(position);

    // BEARING for map rotation - prefer road bearing, fallback to GPS heading
    // GPS heading is only reliable when moving (speed > 0.5 m/s)
    double targetBearing;
    if (_roadBearing != 0) {
      targetBearing = _roadBearing;
    } else if (position.heading >= 0 && position.speed > 0.5) {
      targetBearing = position.heading;
    } else {
      targetBearing = _smoothedBearing; // Keep current if no valid source
    }

    // Update smoothed bearing
    if (_smoothedBearing == 0) {
      // First time - set directly
      _smoothedBearing = targetBearing;
    } else if (targetBearing != _smoothedBearing) {
      // Smooth bearing transition (handle 360/0 wraparound)
      double diff = targetBearing - _smoothedBearing;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      _smoothedBearing = (_smoothedBearing + diff * 0.5) % 360;
      if (_smoothedBearing < 0) _smoothedBearing += 360;
    }

    // SMOOTH POSITION - Use road-snapped position when available for accuracy
    // This keeps the marker on the road instead of drifting off
    if (_smoothedLat == 0) {
      _smoothedLat = position.latitude;
      _smoothedLon = position.longitude;
    } else {
      // If we have a snapped position (on road), blend towards it for accuracy
      // Otherwise use GPS position with interpolation
      double targetLat;
      double targetLon;

      if (_snappedLatLng != null && distanceFromRoute < 30) {
        // On road - snap to road polyline for accuracy
        targetLat = _snappedLatLng!.latitude;
        targetLon = _snappedLatLng!.longitude;
        // Faster blend when snapping to road (0.3/0.7)
        _smoothedLat = _smoothedLat * 0.3 + targetLat * 0.7;
        _smoothedLon = _smoothedLon * 0.3 + targetLon * 0.7;
      } else {
        // Off road or no snap - use GPS with gentle smoothing
        targetLat = position.latitude;
        targetLon = position.longitude;
        // Very responsive when off road (0.2/0.8)
        _smoothedLat = _smoothedLat * 0.2 + targetLat * 0.8;
        _smoothedLon = _smoothedLon * 0.2 + targetLon * 0.8;
      }
    }

    // OFF-ROUTE DETECTION
    if (distanceFromRoute > _offRouteThresholdMeters) {
      if (!_isOffRoute && !_isRecalculatingRoute) {
        _isOffRoute = true;
        _recalculateRoute();
      }
    } else {
      _isOffRoute = false;
    }

    // ROBUST TOLL PLAZA TRACKING with hysteresis to prevent flip-flop
    // Uses: confirmed index, distance threshold, and debounce timing
    _updatePointProgress(position);

    // Distances are calculated correctly in _loadRoute
    // DON'T recalculate during navigation - just keep them as-is
    // They're cumulative road distances which don't need real-time updates

    _updateCurrentNavigationStep(position);

    // Update TARGET position for smooth 60fps animation (ticker will interpolate)
    if (_isNavigating && _isFollowingUser) {
      // NO offset - show cursor at actual GPS position for accuracy
      // User's actual location, not offset ahead
      _targetLat = _smoothedLat;
      _targetLon = _smoothedLon;
      _targetBearing = _smoothedBearing;

      // Update motion parameters INSTANTLY for lightning-fast response
      final bearingRad = _smoothedBearing * (3.14159 / 180);
      _motionSpeedMps = _currentSpeed / 3.6; // km/h to m/s - INSTANT
      _motionBearingRad = bearingRad;

      // Faster smoothing for quicker response (0.5/0.5 blend)
      _smoothMotionSpeed = _smoothMotionSpeed * 0.5 + _motionSpeedMps * 0.5;
      _smoothMotionBearing =
          bearingRad; // Use direct bearing, it's already smoothed
    }

    _updateMapMarkers();
    _lastLocationUpdate = now;

    // Only setState for speed/UI updates
    if (mounted) setState(() {});
  }

  /// Start 60fps smooth map animation ticker with CONTINUOUS MOTION
  /// The car keeps moving forward at current speed - never stops/pauses
  void _startMapTicker() {
    _mapTicker?.dispose();
    _lastTickTime = DateTime.now();

    _mapTicker = createTicker((Duration elapsed) {
      if (!mounted ||
          !_isNavigating ||
          !_isFollowingUser ||
          _mapController == null) return;

      final now = DateTime.now();
      final dt = _lastTickTime != null
          ? (now.difference(_lastTickTime!).inMicroseconds / 1000000.0)
              .clamp(0.001, 0.05)
          : 0.016; // ~60fps default
      _lastTickTime = now;

      // === CONTINUOUS FORWARD MOTION ===
      // Move forward continuously based on current speed and bearing
      // This creates the "always moving" effect like Google Maps navigation

      if (_smoothMotionSpeed > 0.5) {
        // Only move if speed > 0.5 m/s (~2 km/h)
        // Calculate how far to move this frame (distance = speed * time)
        final distanceMeters = _smoothMotionSpeed * dt;

        // Convert meters to lat/lon delta
        final latDelta =
            (distanceMeters / 111000.0) * cos(_smoothMotionBearing);
        final lonDelta =
            (distanceMeters / (111000.0 * cos(_displayLat * 3.14159 / 180))) *
                sin(_smoothMotionBearing);

        // Move display position forward
        _displayLat += latDelta;
        _displayLon += lonDelta;

        // Also move target forward to keep the offset consistent
        _targetLat += latDelta;
        _targetLon += lonDelta;
      }

      // === FAST CORRECTION TOWARDS GPS TARGET ===
      // Quick blend towards the actual GPS position for instant response
      final latDiff = _targetLat - _displayLat;
      final lonDiff = _targetLon - _displayLon;

      // Fast correction for lightning-quick GPS sync
      const correctionStrength = 6.0; // Fast correction
      _displayLat += latDiff * correctionStrength * dt;
      _displayLon += lonDiff * correctionStrength * dt;

      // Smooth bearing interpolation with wraparound handling
      double bearingDiff = _targetBearing - _displayBearing;
      if (bearingDiff > 180) bearingDiff -= 360;
      if (bearingDiff < -180) bearingDiff += 360;

      // Fast bearing change
      _displayBearing += bearingDiff * 6.0 * dt;

      // Keep bearing in 0-360 range
      _displayBearing = _displayBearing % 360;
      if (_displayBearing < 0) _displayBearing += 360;

      // Update camera - ALWAYS update when navigating for smooth continuous motion
      _isProgrammaticCameraMove = true;
      _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_displayLat, _displayLon),
            zoom: 18,
            bearing: _displayBearing,
            tilt: 55,
          ),
        ),
      );
      _isProgrammaticCameraMove = false;

      // Update user location marker at ~30fps for ultra-smooth movement
      _markerUpdateCounter++;
      if (_markerUpdateCounter >= 2) {
        // Every 2nd tick (~30fps)
        _markerUpdateCounter = 0;
        _updateUserMarkerOnly();
      }
    });

    _mapTicker!.start();
  }

  int _markerUpdateCounter = 0;

  /// Update only the user location marker (called ~30fps for ultra-smooth movement)
  void _updateUserMarkerOnly() {
    if (_currentPosition == null) return;

    // Remove old user marker
    _markers.removeWhere((m) => m.markerId.value == 'current_location');

    // Use the actual smoothed GPS position for marker (not display position)
    // This keeps the marker aligned with real location while camera moves smoothly
    final markerLat =
        _smoothedLat != 0 ? _smoothedLat : _currentPosition!.latitude;
    final markerLon =
        _smoothedLon != 0 ? _smoothedLon : _currentPosition!.longitude;
    final displayPosition = LatLng(markerLat, markerLon);

    // Choose icon based on mode (always use nav icon when navigating)
    BitmapDescriptor markerIcon;

    if (_isNavigating) {
      // Always use navigation icon when navigating
      if (_useCarIcon && _carIcon != null) {
        markerIcon = _carIcon!;
      } else if (_navigationArrowIcon != null) {
        markerIcon = _navigationArrowIcon!;
      } else {
        markerIcon =
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      }
    } else {
      // Not navigating - use blue dot
      markerIcon = _blueDotIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    }

    _markers.add(
      Marker(
        markerId: const MarkerId('current_location'),
        position: displayPosition,
        icon: markerIcon,
        rotation: _isNavigating ? _displayBearing : 0,
        anchor: const Offset(0.5, 0.5),
        flat: _isNavigating,
        zIndex: 100,
      ),
    );

    // Force marker update
    if (mounted) setState(() {});
  }

  // Flag to prevent multiple simultaneous route recalculations
  bool _isRecalculatingRoute = false;

  /// Recalculate route when user goes off-route - FAST like Google Maps
  Future<void> _recalculateRoute() async {
    if (_currentPosition == null || _toId == null) return;
    if (_isRecalculatingRoute) return;

    _isRecalculatingRoute = true;
    debugPrint('🔄 Recalculating route from current position...');

    try {
      final destination = _routePoints.last.point;
      final routeData = await TravelWeatherService.instance.getRoutePolyline(
        startLat: _currentPosition!.latitude,
        startLon: _currentPosition!.longitude,
        endLat: destination.lat,
        endLon: destination.lon,
      );

      if (routeData != null && mounted) {
        _roadRoutePoints = routeData.polylinePoints
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
        _navigationSteps = routeData.steps;
        _currentStepIndex = 0;
        _closestPolylineIndex = 0;
        _routeDistanceMeters = routeData.distanceMeters;
        _routeDurationSeconds = routeData.durationSeconds;

        _updateMapMarkers();
        setState(() => _isOffRoute = false);

        debugPrint(
            '✅ Route recalculated with ${_roadRoutePoints.length} points');
      }
    } catch (e) {
      debugPrint('❌ Error recalculating route: $e');
    } finally {
      _isRecalculatingRoute = false;
    }
  }

  /// Calculate road bearing from polyline for smoother navigation
  /// This gives more accurate direction than GPS heading when following the road
  /// Returns the distance from the route (for off-route detection)
  double _calculateRoadBearing(Position position) {
    if (_roadRoutePoints.length < 2) return 0;

    // Find closest point on polyline with more efficient algorithm
    double minDistance = double.infinity;
    int closestIndex = 0;
    LatLng? snappedPosition;

    // Start search from current index for efficiency
    final searchStart = max(0, _closestPolylineIndex - 10);
    final searchEnd = min(_roadRoutePoints.length, _closestPolylineIndex + 50);

    for (int i = searchStart; i < searchEnd; i++) {
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
        snappedPosition = point;
      }
    }

    // If not found in narrow range, search entire route
    if (minDistance > 200) {
      for (int i = 0; i < _roadRoutePoints.length; i++) {
        if (i >= searchStart && i < searchEnd) continue;
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
          snappedPosition = point;
        }
      }
    }

    _closestPolylineIndex = closestIndex;

    // SNAP TO ROAD: Interpolate position onto the road segment for smooth tracking
    // Instead of just using discrete polyline points, project onto the line segment
    if (minDistance < 100 && closestIndex < _roadRoutePoints.length - 1) {
      // Get the road segment we're closest to
      final p1 = _roadRoutePoints[closestIndex];
      final p2 = _roadRoutePoints[closestIndex + 1];

      // Project GPS position onto the line segment between p1 and p2
      final snapped = _projectPointOntoSegment(
        position.latitude,
        position.longitude,
        p1.latitude,
        p1.longitude,
        p2.latitude,
        p2.longitude,
      );
      _snappedLatLng = snapped;
    } else if (snappedPosition != null && minDistance < 50) {
      // Fallback: Within 50m - snap to closest point
      _snappedLatLng = snappedPosition;
    } else {
      // Too far from road - use actual position
      _snappedLatLng = null;
    }

    // Calculate bearing to next point on polyline (look ahead for smoother rotation)
    // Look 5-10 points ahead for smoother bearing on motorway
    final lookAhead = min(closestIndex + 10, _roadRoutePoints.length - 1);
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

    return minDistance;
  }

  /// Project a point onto a line segment (for smooth road snapping)
  /// Returns the closest point on the segment to the given point
  LatLng _projectPointOntoSegment(
    double pointLat,
    double pointLon,
    double segStartLat,
    double segStartLon,
    double segEndLat,
    double segEndLon,
  ) {
    // Vector from segment start to end
    final dx = segEndLon - segStartLon;
    final dy = segEndLat - segStartLat;

    // If segment is a point, return that point
    if (dx == 0 && dy == 0) {
      return LatLng(segStartLat, segStartLon);
    }

    // Calculate projection parameter t (0 = start, 1 = end)
    // t = dot(point - start, end - start) / |end - start|^2
    final t = ((pointLon - segStartLon) * dx + (pointLat - segStartLat) * dy) /
        (dx * dx + dy * dy);

    // Clamp t to [0, 1] to stay on segment
    final tClamped = t.clamp(0.0, 1.0);

    // Calculate the projected point
    final projLat = segStartLat + tClamped * dy;
    final projLon = segStartLon + tClamped * dx;

    return LatLng(projLat, projLon);
  }

  // Snapped position on road (for marker display)
  // ignore: unused_field
  LatLng? _snappedLatLng;

  /// Update which navigation step we're currently on
  void _updateCurrentNavigationStep(Position position) {
    if (_navigationSteps.isEmpty) return;

    int previousStepIndex = _currentStepIndex;

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

    // Update notification when step changes
    if (_currentStepIndex != previousStepIndex) {
      _showNavigationNotification();
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
        final metar = await fetchMetar(airport['icao']);
        if (mounted && metar != null) {
          setState(() => _currentLocationMetar = metar);
        }
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

      if (weather.isNotEmpty && mounted) {
        setState(() {
          _currentLocationWeather = {
            'temp_c': weather[0].tempC,
            'humidity': weather[0].humidity,
            'wind_kph': weather[0].windKph,
            'condition': weather[0].condition,
            'icon': weather[0].icon,
          };
        });
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
  /// Between Sunrise and Dhuhr, returns null (no prayer time)
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

    // Get sunrise and dhuhr times for gap detection
    final sunrise = prayers.firstWhere((p) => p.name == 'Sunrise',
        orElse: () => prayers.first);
    final dhuhr = prayers.firstWhere((p) => p.name == 'Dhuhr',
        orElse: () => prayers.first);

    // Check if arrival time is between Sunrise and Dhuhr (no prayer time)
    if (arrivalTime.isAfter(sunrise.time) && arrivalTime.isBefore(dhuhr.time)) {
      // Between Sunrise and Dhuhr - no active prayer
      return {
        'name': null,
        'time': null,
      };
    }

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

  /// Start tracking current prayer time with countdown
  /// Updates every second to show remaining time
  Future<void> _startPrayerCountdown() async {
    _prayerCountdownTimer?.cancel();

    await _updateCurrentPrayer();

    // Update every second for smooth countdown
    _prayerCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // Trigger rebuild for countdown update
    });
  }

  /// Stop prayer countdown timer
  void _stopPrayerCountdown() {
    _prayerCountdownTimer?.cancel();
    _prayerCountdownTimer = null;
  }

  /// Update current prayer based on location
  Future<void> _updateCurrentPrayer() async {
    if (_currentPosition == null) return;

    try {
      final now = DateTime.now();
      final prayerTimes = await PrayerService.calculatePrayerTimes(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        date: now,
      );

      final prayers = prayerTimes.prayers;

      // Get key prayer times
      final fajr = prayers.firstWhere((p) => p.name == 'Fajr',
          orElse: () => prayers.first);
      final sunrise = prayers.firstWhere((p) => p.name == 'Sunrise',
          orElse: () => prayers.first);
      final dhuhr = prayers.firstWhere((p) => p.name == 'Dhuhr',
          orElse: () => prayers.first);
      final asr = prayers.firstWhere((p) => p.name == 'Asr',
          orElse: () => prayers.first);
      final maghrib = prayers.firstWhere((p) => p.name == 'Maghrib',
          orElse: () => prayers.first);
      final isha = prayers.firstWhere((p) => p.name == 'Isha',
          orElse: () => prayers.first);

      String? currentPrayer;
      DateTime? endsAt;

      // Determine current prayer period based on time
      if (now.isBefore(fajr.time)) {
        // Before Fajr - still Isha from yesterday, ends at Fajr
        currentPrayer = 'Isha';
        endsAt = fajr.time;
      } else if (now.isBefore(sunrise.time)) {
        // Fajr time - ends at Sunrise
        currentPrayer = 'Fajr';
        endsAt = sunrise.time;
      } else if (now.isBefore(dhuhr.time)) {
        // Between Sunrise and Dhuhr - Ishraq/Chasht (no obligatory prayer)
        currentPrayer = 'Duha';
        endsAt = dhuhr.time;
      } else if (now.isBefore(asr.time)) {
        // Dhuhr time - ends at Asr
        currentPrayer = 'Dhuhr';
        endsAt = asr.time;
      } else if (now.isBefore(maghrib.time)) {
        // Asr time - ends at Maghrib
        currentPrayer = 'Asr';
        endsAt = maghrib.time;
      } else if (now.isBefore(isha.time)) {
        // Maghrib time - ends at Isha
        currentPrayer = 'Maghrib';
        endsAt = isha.time;
      } else {
        // Isha time - ends at next day's Fajr
        currentPrayer = 'Isha';
        // Calculate next day's Fajr
        final tomorrow = now.add(const Duration(days: 1));
        try {
          final tomorrowPrayers = await PrayerService.calculatePrayerTimes(
            latitude: _currentPosition!.latitude,
            longitude: _currentPosition!.longitude,
            date: tomorrow,
          );
          final tomorrowFajr = tomorrowPrayers.prayers.firstWhere(
            (p) => p.name == 'Fajr',
            orElse: () => tomorrowPrayers.prayers.first,
          );
          endsAt = tomorrowFajr.time;
        } catch (e) {
          // Fallback: estimate next Fajr as current Fajr + 24 hours
          endsAt = fajr.time.add(const Duration(days: 1));
        }
      }

      debugPrint('🕌 Current prayer: $currentPrayer, ends at: $endsAt');

      if (mounted) {
        setState(() {
          _currentPrayerName = currentPrayer;
          _currentPrayerEndsAt = endsAt;
        });
      }
    } catch (e) {
      debugPrint('Error updating current prayer: $e');
    }
  }

  /// Get formatted countdown string for prayer
  String _getPrayerCountdown() {
    if (_currentPrayerEndsAt == null || _currentPrayerName == null) {
      return '';
    }

    final now = DateTime.now();
    final remaining = _currentPrayerEndsAt!.difference(now);

    if (remaining.isNegative) {
      // Prayer time has passed, schedule refresh (don't call directly to avoid loop)
      Future.microtask(() => _updateCurrentPrayer());
      return '';
    }

    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m ${remaining.inSeconds % 60}s left';
    } else {
      return '${remaining.inSeconds}s left';
    }
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

    // Clear old caches to ensure fresh data
    TravelWeatherService.instance.clearWeatherCache();
    _metarData.clear();
    _forceMetarRefresh = true; // Force fresh METAR fetch

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Wait for GPS position if not available (max 5 seconds)
      if (_currentPosition == null) {
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_currentPosition != null) break;
        }
      }

      // Get points for the route
      List<MotorwayPoint> points;
      if (_fromId == null) {
        // From current location to destination
        // Get all points on the motorway
        final allPoints =
            PakistanMotorways.getPointsTo(_selectedMotorwayId, _toId!);

        // Filter to only include points between user and destination
        // Direction is determined by comparing user position to destination
        if (_currentPosition != null && allPoints.length > 1) {
          points = _filterPointsOnRoute(allPoints, _toId!);
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
        _isLoadingRoute = false;
        setState(() => _isLoading = false);
        return;
      }

      // Get starting coordinates
      final startLat = _currentPosition?.latitude ?? points.first.lat;
      final startLon = _currentPosition?.longitude ?? points.first.lon;
      final endLat = points.last.lat;
      final endLon = points.last.lon;

      // Use straight line route initially (instant, no network)
      _roadRoutePoints = [
        LatLng(startLat, startLon),
        ...points.map((p) => LatLng(p.lat, p.lon)),
      ];
      _navigationSteps = [];

      // Calculate route distance - handle reverse direction properly
      // Distance is the absolute difference between first and last point's distanceFromStart
      final firstPointDist = points.first.distanceFromStart;
      final lastPointDist = points.last.distanceFromStart;
      final routeDistanceKm = (lastPointDist - firstPointDist).abs();
      _routeDistanceMeters = (routeDistanceKm * 1000).round();

      // STORE the reference point for ETA calculations
      _firstPointDistFromStart = firstPointDist.toDouble();

      // Calculate distance from user to FIRST toll plaza (GPS distance)
      int distanceToFirstPlaza = 0;
      if (_currentPosition != null && points.isNotEmpty) {
        final distMeters = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          points.first.lat,
          points.first.lon,
        );
        distanceToFirstPlaza = (distMeters / 1000).round();
      }

      // Calculate cumulative distances from user
      // First plaza = GPS distance, rest = first plaza + road distance between plazas
      final distancesFromUser = <int>[];
      for (int i = 0; i < points.length; i++) {
        // Road distance from first plaza to this plaza
        final roadDistFromFirst =
            (points[i].distanceFromStart - _firstPointDistFromStart)
                .abs()
                .round();
        // Total distance = GPS to first + road from first to this
        final totalDistFromUser = distanceToFirstPlaza + roadDistFromFirst;
        distancesFromUser.add(totalDistFromUser);
      }

      // Calculate ETAs using distance-based estimation (100 km/h average)
      final etas = distancesFromUser.map((distKm) {
        final minutes = (distKm / 100 * 60).round();
        return Duration(minutes: minutes);
      }).toList();

      // Estimate total duration from route distance
      _routeDurationSeconds = etas.isNotEmpty ? etas.last.inSeconds : 0;

      // Build travel points with dynamic distance from user
      final now = DateTime.now();
      final travelPoints = <TravelPoint>[];
      for (int i = 0; i < points.length; i++) {
        final point = points[i];
        final eta = i < etas.length ? etas[i] : null;
        final estimatedArrival = eta != null ? now.add(eta) : null;
        final distFromUser =
            i < distancesFromUser.length ? distancesFromUser[i] : 0;
        travelPoints.add(TravelPoint(
          point: point,
          etaFromStart: eta,
          estimatedArrival: estimatedArrival,
          weather: null,
          nextPrayer: null,
          nextPrayerTime: null,
          distanceFromUser: distFromUser,
        ));
      }

      _routePoints = travelPoints;

      // Show UI immediately
      _updateMapMarkers();
      _isLoadingRoute = false;
      setState(() => _isLoading = false);

      // Fetch Google Directions in background for accurate road polyline
      _fetchGoogleDirectionsInBackground(
          startLat, startLon, endLat, endLon, points, etas);

      // Fetch weather and prayer times in background
      _fetchWeatherAndPrayersInBackground(points, etas);

      // Fetch METAR data in background
      _fetchMetarForRoute();
    } catch (e) {
      setState(() => _error = 'Failed to load route: $e');
      _isLoadingRoute = false;
      setState(() => _isLoading = false);
    }
  }

  /// Fetch Google Directions API in background for accurate road route
  Future<void> _fetchGoogleDirectionsInBackground(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
    List<MotorwayPoint> points,
    List<Duration> etas,
  ) async {
    try {
      final routeData = await TravelWeatherService.instance.getRoutePolyline(
        startLat: startLat,
        startLon: startLon,
        endLat: endLat,
        endLon: endLon,
        waypoints: null,
      );

      if (routeData != null && mounted) {
        _roadRoutePoints = routeData.polylinePoints
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
        _routeDistanceMeters = routeData.distanceMeters;
        _routeDurationSeconds = routeData.durationSeconds;
        _navigationSteps = routeData.steps;

        // Recalculate ETAs with actual duration - handle reverse direction
        final totalSeconds = routeData.durationSeconds;
        final totalDistance = routeData.distanceMeters / 1000.0; // in km
        final now = DateTime.now();

        final updatedPoints = <TravelPoint>[];
        for (int i = 0; i < _routePoints.length && i < points.length; i++) {
          final existing = _routePoints[i];
          // Calculate ETA based on road distance fraction
          final roadDistFromFirst =
              (points[i].distanceFromStart - _firstPointDistFromStart).abs();
          final fraction =
              totalDistance > 0 ? roadDistFromFirst / totalDistance : 0.0;
          final seconds = (totalSeconds * fraction).round();
          final eta = Duration(seconds: seconds);

          updatedPoints.add(TravelPoint(
            point: existing.point,
            etaFromStart: eta,
            estimatedArrival: now.add(eta),
            weather: existing.weather,
            nextPrayer: existing.nextPrayer,
            nextPrayerTime: existing.nextPrayerTime,
            distanceFromUser:
                existing.distanceFromUser, // PRESERVE existing distance
          ));
        }
        _routePoints = updatedPoints;

        debugPrint(
            '✅ Google Directions loaded: ${_roadRoutePoints.length} points');
        _updateMapMarkers();
        setState(() {});
      }
    } catch (e) {
      debugPrint('⚠️ Google Directions failed: $e (using fallback route)');
    }
  }

  /// Fetch weather and prayer times in background and update UI when ready
  Future<void> _fetchWeatherAndPrayersInBackground(
    List<MotorwayPoint> points,
    List<Duration> etas,
  ) async {
    try {
      final now = DateTime.now();

      // Fetch weather for ALL route points
      final keyPoints = _getKeyPointsForWeather(points);
      final weatherList =
          await TravelWeatherService.instance.getWeatherForPoints(keyPoints);

      // Create a map of weather by point ID for quick lookup
      final weatherMap = <String, TravelWeather>{};
      for (int i = 0; i < keyPoints.length && i < weatherList.length; i++) {
        weatherMap[keyPoints[i].id] = weatherList[i];
      }

      // Fetch all prayer times in parallel
      final prayerFutures = points.asMap().entries.map((entry) async {
        final i = entry.key;
        final point = entry.value;
        final eta = i < etas.length ? etas[i] : null;
        final estimatedArrival = eta != null ? now.add(eta) : null;
        if (estimatedArrival == null) return <String, String?>{};
        try {
          return await _getPrayerAtArrivalTime(
            latitude: point.lat,
            longitude: point.lon,
            arrivalTime: estimatedArrival,
          );
        } catch (_) {
          return <String, String?>{};
        }
      }).toList();

      final prayerResults = await Future.wait(prayerFutures);

      // Update route points with weather and prayer data
      if (mounted && _routePoints.isNotEmpty) {
        final updatedPoints = <TravelPoint>[];
        for (int i = 0; i < _routePoints.length && i < points.length; i++) {
          final existing = _routePoints[i];
          final weather = weatherMap[existing.point.id];
          final prayerData =
              i < prayerResults.length ? prayerResults[i] : <String, String?>{};
          updatedPoints.add(TravelPoint(
            point: existing.point,
            etaFromStart: existing.etaFromStart,
            estimatedArrival: existing.estimatedArrival,
            weather: weather ?? existing.weather,
            nextPrayer: prayerData['name'] ?? existing.nextPrayer,
            nextPrayerTime: prayerData['time'] ?? existing.nextPrayerTime,
            distanceFromUser:
                existing.distanceFromUser, // PRESERVE existing distance
          ));
        }
        _routePoints = updatedPoints;
        debugPrint(
            '✅ Weather and prayer data loaded for ${updatedPoints.length} points');
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('⚠️ Background weather/prayer fetch failed: $e');
    }
  }

  // Flag to force fresh METAR fetch (set to true when route changes)
  bool _forceMetarRefresh = true;

  Future<void> _fetchMetarForRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = WeatherController();

    // Step 1: Group points by their nearest airport ICAO to avoid duplicate fetches
    final Map<String, List<Map<String, dynamic>>> airportToPoints = {};
    final Map<String, Map<String, dynamic>> pointToAirportInfo = {};

    for (final tp in _routePoints) {
      final cacheKey = 'metar_${tp.point.id}';

      // Check cache first (unless force refresh is on)
      if (!_forceMetarRefresh) {
        final cached = prefs.getString(cacheKey);
        if (cached != null) {
          final data = jsonDecode(cached);
          final fetchedAt = DateTime.parse(data['fetched_at']);
          if (DateTime.now().difference(fetchedAt).inMinutes < 20) {
            _metarData[tp.point.id] = data['metar'];
            continue;
          }
        }
      }

      // Find nearest airport
      var airport =
          controller.getAirportFromCoordinates(tp.point.lat, tp.point.lon);
      airport ??= controller.getNearestAirport(tp.point.lat, tp.point.lon,
          maxDistanceKm: 100);

      if (airport != null) {
        final icao = airport['icao'] as String;
        final distanceKm = airport['distance'] as double? ?? 0.0;
        final airportRadius = airport['radius'] as double? ?? 30.0;
        debugPrint(
            '🛫 Point ${tp.point.name}: found airport $icao at ${distanceKm.toStringAsFixed(1)}km (radius: ${airportRadius}km)');

        airportToPoints.putIfAbsent(icao, () => []);
        airportToPoints[icao]!.add({
          'point': tp,
          'distance': distanceKm,
          'radius': airportRadius,
          'cacheKey': cacheKey,
        });
        pointToAirportInfo[tp.point.id] = airport;
      } else {
        debugPrint('⚠️ Point ${tp.point.name}: NO airport found within 100km');
      }
    }

    // Step 2: Fetch METAR for each unique ICAO in parallel
    final icaoCodes = airportToPoints.keys.toList();
    if (icaoCodes.isEmpty) {
      debugPrint(
          '❌ No airports found for any route points - METAR will not be fetched');
      setState(() {});
      return;
    }

    debugPrint(
        '📡 Fetching METAR for ${icaoCodes.length} unique airports in parallel...');

    final metarFutures = icaoCodes.map((icao) async {
      try {
        return MapEntry(icao, await fetchMetar(icao));
      } catch (e) {
        debugPrint('❌ METAR fetch error for $icao: $e');
        return MapEntry(icao, null);
      }
    }).toList();

    final metarResults = await Future.wait(metarFutures);
    final metarByIcao =
        Map.fromEntries(metarResults.where((e) => e.value != null));

    // Step 3: Assign METAR data to all points that share the same airport
    for (final icao in metarByIcao.keys) {
      final metar = metarByIcao[icao]!;
      final pointsList = airportToPoints[icao]!;

      for (final pointData in pointsList) {
        final tp = pointData['point'] as TravelPoint;
        final distanceKm = pointData['distance'] as double;
        final airportRadius = pointData['radius'] as double;
        final cacheKey = pointData['cacheKey'] as String;

        // Store METAR with distance info
        final metarWithDistance = Map<String, dynamic>.from(metar);
        metarWithDistance['_airport_distance_km'] = distanceKm;
        metarWithDistance['_airport_radius_km'] = airportRadius;
        metarWithDistance['_airport_icao'] = icao;
        _metarData[tp.point.id] = metarWithDistance;

        // Cache it
        prefs.setString(
          cacheKey,
          jsonEncode({
            'fetched_at': DateTime.now().toIso8601String(),
            'metar': metarWithDistance,
          }),
        );
      }
    }

    debugPrint(
        '📊 METAR data collected for ${_metarData.length} points from ${metarByIcao.length} airports');

    // Reset force refresh flag after successful fetch
    _forceMetarRefresh = false;

    if (mounted) setState(() {});
  }

  /// Safely parse a value to double (handles both num and String)
  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Check if METAR data should be used (within airport radius, default 30km)
  /// Returns true only if METAR exists and point is within the airport's coverage radius
  bool _shouldUseMetar(Map<String, dynamic>? metar) {
    if (metar == null) return false;
    final distance = _toDouble(metar['_airport_distance_km']);
    final radius = _toDouble(metar['_airport_radius_km']) ?? 30.0;
    if (distance == null) return false;
    return distance <= radius;
  }

  /// Extract primary METAR code from raw METAR text - matches WeatherController logic
  String _extractMetarCode(String metarRawText) {
    metarRawText = metarRawText.toUpperCase();

    if (metarRawText.contains("TSRA")) return "TSRA";
    if (metarRawText.contains("TS")) return "TS";
    if (metarRawText.contains("SHRA")) return "SHRA";
    if (metarRawText.contains("RA")) return "RA";
    if (metarRawText.contains("SN")) return "SN";
    if (metarRawText.contains("DZ")) return "DZ";
    if (metarRawText.contains("FG")) return "FG";
    if (metarRawText.contains("BR")) return "BR";
    if (metarRawText.contains("HZ")) return "HZ";
    if (metarRawText.contains("FU")) return "FU";
    if (metarRawText.contains("DU")) return "DU";
    if (metarRawText.contains("SA")) return "SA";
    if (metarRawText.contains("OVC")) return "OVC";
    if (metarRawText.contains("BKN")) return "BKN";
    if (metarRawText.contains("SCT")) return "SCT";
    if (metarRawText.contains("FEW")) return "FEW";

    return "SKC";
  }

  /// Robust point progress tracking with hysteresis to prevent flip-flopping
  /// Uses committed index that only advances forward, with distance and bearing checks
  void _updatePointProgress(Position position) {
    if (_routePoints.isEmpty) return;

    final now = DateTime.now();

    // ANTI-REGRESSION: Ensure we never go below the highest achieved index
    // This prevents screen-off GPS glitches from jumping back to previous plazas
    if (_confirmedPointIndex < _highestAchievedIndex) {
      _confirmedPointIndex = _highestAchievedIndex;
      _currentPointIndex = _highestAchievedIndex;
      debugPrint(
          '🛡️ ANTI-REGRESSION: Restored to highest achieved index $_highestAchievedIndex');
    }

    // Check if we should advance to the next point
    // Only advance if we've definitively passed the current point
    if (_confirmedPointIndex < _routePoints.length) {
      final currentPoint = _routePoints[_confirmedPointIndex].point;
      final distToCurrent = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        currentPoint.lat,
        currentPoint.lon,
      );

      // Check distance to next point (if exists)
      MotorwayPoint? nextPoint;
      if (_confirmedPointIndex + 1 < _routePoints.length) {
        nextPoint = _routePoints[_confirmedPointIndex + 1].point;
      }

      // CHECK FOR DESTINATION ARRIVAL
      // If this is the last point (destination) and we're within 100m, show arrived
      final isDestination = _confirmedPointIndex == _routePoints.length - 1;
      if (isDestination && distToCurrent < 100 && !_hasArrived) {
        _hasArrived = true;
        _showArrivedDialog();
        debugPrint('🎉 ARRIVED at destination: ${currentPoint.name}');
        if (mounted) setState(() {});
        return; // Don't process further - we've arrived
      }

      // BEARING-BASED LOGIC: Switch immediately when you've PASSED the toll plaza
      // The toll plaza is "behind you" when the bearing from you to it points backward

      bool shouldAdvance = false;

      if (nextPoint != null) {
        // Calculate bearing from USER to CURRENT point
        double bearingToCurrentPoint = Geolocator.bearingBetween(
          position.latitude,
          position.longitude,
          currentPoint.lat,
          currentPoint.lon,
        );

        // Calculate bearing from USER to NEXT point (travel direction)
        double bearingToNextPoint = Geolocator.bearingBetween(
          position.latitude,
          position.longitude,
          nextPoint.lat,
          nextPoint.lon,
        );

        // Normalize bearings to 0-360
        if (bearingToCurrentPoint < 0) bearingToCurrentPoint += 360;
        if (bearingToNextPoint < 0) bearingToNextPoint += 360;

        // Calculate the difference - if current point is roughly OPPOSITE to travel direction, we've passed it
        double bearingDiff = (bearingToCurrentPoint - bearingToNextPoint).abs();
        if (bearingDiff > 180) bearingDiff = 360 - bearingDiff;

        // If bearing difference > 90°, current point is behind us (we've passed it)
        // Current point is to our back, next point is ahead
        final currentPointIsBehind = bearingDiff > 90;

        if (currentPointIsBehind) {
          shouldAdvance = true;
          debugPrint(
              '📍 PASSED ${currentPoint.name}: It\'s behind us (bearing diff: ${bearingDiff.toStringAsFixed(0)}°) → Next: ${nextPoint.name}');
        }
      }

      // STARTUP GRACE PERIOD: If we just started and are near a point, wait for clear pass
      final isFirstChange = _lastPointChangeTime == null;
      if (isFirstChange && distToCurrent < 300) {
        // On startup near a point, require stronger confirmation (> 120° behind)
        if (nextPoint != null) {
          double bearingToCurrentPoint = Geolocator.bearingBetween(
            position.latitude,
            position.longitude,
            currentPoint.lat,
            currentPoint.lon,
          );
          double bearingToNextPoint = Geolocator.bearingBetween(
            position.latitude,
            position.longitude,
            nextPoint.lat,
            nextPoint.lon,
          );
          if (bearingToCurrentPoint < 0) bearingToCurrentPoint += 360;
          if (bearingToNextPoint < 0) bearingToNextPoint += 360;
          double bearingDiff =
              (bearingToCurrentPoint - bearingToNextPoint).abs();
          if (bearingDiff > 180) bearingDiff = 360 - bearingDiff;

          if (bearingDiff <= 120) {
            shouldAdvance = false;
            debugPrint(
                '⏳ Startup near ${currentPoint.name}: waiting for clear pass (${bearingDiff.toStringAsFixed(0)}°)');
          }
        }
      }

      // Debounce: Minimum 300ms between point changes for instant response
      final canChangePoint = _lastPointChangeTime == null ||
          now.difference(_lastPointChangeTime!).inMilliseconds > 300;

      if (shouldAdvance && canChangePoint) {
        final newIndex = _confirmedPointIndex + 1;

        // MONOTONIC PROGRESSION: Never go backward
        // This prevents screen-off GPS glitches from regressing to previous plazas
        if (newIndex > _highestAchievedIndex) {
          _highestAchievedIndex = newIndex;
        }

        _confirmedPointIndex = newIndex;
        _currentPointIndex = newIndex;
        _lastPointChangeTime = now;

        // DON'T update distances - they're correct from initial load
        // Just update ETAs based on current position
        _updateDynamicETAs(position);

        _saveNavigationProgress();
        debugPrint(
            '✅ PASSED: ${currentPoint.name} → Now tracking: ${nextPoint?.name ?? "destination"} (highest: $_highestAchievedIndex)');

        // Force UI update for timeline
        if (mounted) setState(() {});
      }
    }
  }

  /// Update ETAs for all remaining points based on current position
  /// NOTE: Does NOT update distanceFromUser - that's handled by _updateDynamicDistances
  void _updateDynamicETAs(Position position) {
    if (_routePoints.isEmpty || _routeDurationSeconds == 0) return;

    final now = DateTime.now();
    final avgSpeedMps = _routeDistanceMeters /
        _routeDurationSeconds; // Average speed from original route

    // Use current speed if available, otherwise use route average
    final speedToUse = _currentSpeed > 0
        ? _currentSpeed * 1000 / 3600 // Convert km/h to m/s
        : avgSpeedMps;

    // Calculate GPS distance to first point for cumulative ETA
    final firstPoint = _routePoints.first;
    final distToFirstMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      firstPoint.point.lat,
      firstPoint.point.lon,
    );
    final firstPointDistFromStart = firstPoint.point.distanceFromStart;

    final updatedPoints = <TravelPoint>[];

    for (int i = 0; i < _routePoints.length; i++) {
      final tp = _routePoints[i];

      // Calculate cumulative distance for ETA (GPS to first + road from first to this)
      final roadDistFromFirstMeters =
          (tp.point.distanceFromStart - firstPointDistFromStart).abs() * 1000;
      final totalDistanceMeters = distToFirstMeters + roadDistFromFirstMeters;

      // Calculate ETA based on cumulative distance and speed
      final etaSeconds =
          speedToUse > 0 ? (totalDistanceMeters / speedToUse).round() : 0;
      final eta = Duration(seconds: etaSeconds);

      updatedPoints.add(TravelPoint(
        point: tp.point,
        etaFromStart: eta,
        estimatedArrival: now.add(eta),
        weather: tp.weather,
        nextPrayer: tp.nextPrayer,
        nextPrayerTime: tp.nextPrayerTime,
        distanceFromUser: tp.distanceFromUser, // PRESERVE existing distance
      ));
    }

    _routePoints = updatedPoints;
  }

  /// Show arrival dialog when user reaches destination
  void _showArrivedDialog() {
    if (_arrivedDialogShown || !mounted) return;
    _arrivedDialogShown = true;

    final destination = _routePoints.isNotEmpty
        ? _routePoints.last.point.name
        : 'your destination';

    // Stop navigation when arrived
    _stopNavigation();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Large checkmark icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
            ),
            const SizedBox(height: 20),
            const Text(
              'You have arrived!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              destination,
              style: TextStyle(
                color: _orangeAccent,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Thanks for using Weather Alert PK',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _orangeAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                // Reset and go back to route selection
                setState(() {
                  _routeConfirmed = false;
                  _hasArrived = false;
                  _arrivedDialogShown = false;
                  _routePoints.clear();
                  _toId = null;
                });
              },
              child: const Text(
                'Done',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Update route points with dynamic distances from current position
  /// Uses cumulative: GPS to FIRST plaza + road distance between plazas
  /// Same calculation as _loadRoute for consistency
  // ignore: unused_element
  void _updateDynamicDistances(Position position) {
    if (_routePoints.isEmpty) return;

    // GPS distance to FIRST plaza
    final firstPoint = _routePoints.first;
    final distToFirstPlaza = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      firstPoint.point.lat,
      firstPoint.point.lon,
    );
    final distToFirstPlazaKm = (distToFirstPlaza / 1000).round();

    for (int i = 0; i < _routePoints.length; i++) {
      final tp = _routePoints[i];

      // Road distance from first plaza to this plaza (using stored reference)
      final roadDistFromFirst =
          (tp.point.distanceFromStart - _firstPointDistFromStart).abs().round();

      // Total = GPS to first + road from first to this
      final totalDist = distToFirstPlazaKm + roadDistFromFirst;

      _routePoints[i] = tp.copyWith(
        distanceFromUser: totalDist,
      );
    }
  }

  /// Save navigation progress
  Future<void> _saveNavigationProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('nav_current_point_index', _currentPointIndex);
    await prefs.setBool('nav_is_navigating', _isNavigating);
    await prefs.setString('nav_route_id', '${_fromId ?? "current"}_to_$_toId');
  }

  // Custom marker icons for navigation
  BitmapDescriptor? _navigationArrowIcon;
  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _blueDotIcon;

  /// Create custom navigation icons programmatically
  Future<void> _createCustomMarkerIcons() async {
    // Create navigation arrow icon (like Google Maps blue arrow)
    _navigationArrowIcon = await _createNavigationArrowIcon();

    // Create car icon
    _carIcon = await _createCarIcon();

    // Create blue dot for when not navigating
    _blueDotIcon = await _createBlueDotIcon();

    // Update markers if we already have position
    if (mounted && _currentPosition != null) {
      setState(() {
        _updateMapMarkers();
      });
    }
  }

  /// Create a blue dot icon for when not navigating
  Future<BitmapDescriptor> _createBlueDotIcon() async {
    final pictureRecorder = PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const size = 60.0;

    // Outer glow
    final glowPaint = Paint()
      ..color = const Color(0xFF4285F4).withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, glowPaint);

    // Blue dot
    final dotPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 3, dotPaint);

    // White border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 3, borderPaint);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    if (byteData != null) {
      return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
  }

  /// Create a navigation arrow icon programmatically - LARGE like Google Maps
  Future<BitmapDescriptor> _createNavigationArrowIcon() async {
    try {
      final pictureRecorder = PictureRecorder();
      final canvas = Canvas(pictureRecorder);
      const double size = 96.0; // Good size for visibility

      // Draw outer glow circle
      final glowPaint = Paint()
        ..color = const Color(0xFF4285F4).withOpacity(0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, glowPaint);

      // Draw main blue circle
      final bgPaint = Paint()
        ..color = const Color(0xFF4285F4) // Google Blue
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
          const Offset(size / 2, size / 2), size / 2 - 6, bgPaint);

      // Draw white border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(
          const Offset(size / 2, size / 2), size / 2 - 7, borderPaint);

      // Draw arrow pointing up (like Google Maps navigation arrow)
      final arrowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      final arrowPath = Path()
        ..moveTo(size / 2, 16) // Top point
        ..lineTo(size / 2 + 22, size - 22) // Bottom right
        ..lineTo(size / 2, size - 32) // Center notch
        ..lineTo(size / 2 - 22, size - 22) // Bottom left
        ..close();
      canvas.drawPath(arrowPath, arrowPaint);

      final picture = pictureRecorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData != null) {
        debugPrint('✅ Navigation arrow icon created successfully');
        return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('❌ Error creating navigation arrow icon: $e');
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  }

  /// Create a car icon programmatically - LARGE
  Future<BitmapDescriptor> _createCarIcon() async {
    try {
      final pictureRecorder = PictureRecorder();
      final canvas = Canvas(pictureRecorder);
      const double size = 96.0;

      // Draw blue circle background
      final bgPaint = Paint()
        ..color = const Color(0xFF1565C0) // Dark Blue
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
          const Offset(size / 2, size / 2), size / 2 - 4, bgPaint);

      // Draw white border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(
          const Offset(size / 2, size / 2), size / 2 - 5, borderPaint);

      // Draw simplified car shape pointing up
      final carPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      // Car body
      final carPath = Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: const Offset(size / 2, size / 2 + 4),
              width: 28,
              height: 40),
          const Radius.circular(6),
        ));
      canvas.drawPath(carPath, carPaint);

      // Car windshield (darker)
      final windowPaint = Paint()
        ..color = const Color(0xFF1565C0)
        ..style = PaintingStyle.fill;
      final windowPath = Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: const Offset(size / 2, size / 2 - 4),
              width: 20,
              height: 12),
          const Radius.circular(3),
        ));
      canvas.drawPath(windowPath, windowPaint);

      // Front indicator (direction)
      final frontPaint = Paint()
        ..color = const Color(0xFFFFEB3B) // Yellow
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(size / 2, 20), 6, frontPaint);

      final picture = pictureRecorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData != null) {
        debugPrint('✅ Car icon created successfully');
        return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('❌ Error creating car icon: $e');
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  /// Create weather card marker with icon, temperature, and visibility
  Future<BitmapDescriptor> _createWeatherCardMarker({
    required int temp,
    required String condition,
    String? visibility,
    bool isNext = false,
    bool isPassed = false,
  }) async {
    final pictureRecorder = PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const width = 80.0;
    const height = 50.0;

    // Card background
    final bgPaint = Paint()
      ..color = isPassed
          ? const Color(0xFF4A4A4C) // Grey for passed
          : isNext
              ? const Color(0xFF00C7BE) // Teal for next
              : const Color(0xFF2C2C2E) // Dark card
      ..style = PaintingStyle.fill;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(10),
    );
    canvas.drawRRect(rrect, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = isNext ? const Color(0xFF00C7BE) : const Color(0xFF48484A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    // Weather icon placeholder (circle with emoji-like representation)
    final iconPaint = Paint()
      ..color = _getWeatherColor(condition)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(18, height / 2), 12, iconPaint);

    // Draw a simple sun/cloud/rain symbol
    final iconSymbolPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    if (condition.toLowerCase().contains('sun') ||
        condition.toLowerCase().contains('clear')) {
      // Sun rays
      for (int i = 0; i < 8; i++) {
        final angle = i * pi / 4;
        canvas.drawLine(
          Offset(18 + cos(angle) * 6, height / 2 + sin(angle) * 6),
          Offset(18 + cos(angle) * 10, height / 2 + sin(angle) * 10),
          iconSymbolPaint..strokeWidth = 2,
        );
      }
      canvas.drawCircle(const Offset(18, height / 2), 5, iconSymbolPaint);
    } else if (condition.toLowerCase().contains('rain')) {
      // Rain drops
      canvas.drawCircle(const Offset(18, height / 2 - 3), 6, iconSymbolPaint);
      for (int i = 0; i < 3; i++) {
        canvas.drawLine(
          Offset(14.0 + i * 4, height / 2 + 4),
          Offset(12.0 + i * 4, height / 2 + 9),
          iconSymbolPaint..strokeWidth = 2,
        );
      }
    } else {
      // Cloud
      canvas.drawCircle(const Offset(15, height / 2), 5, iconSymbolPaint);
      canvas.drawCircle(const Offset(21, height / 2), 6, iconSymbolPaint);
      canvas.drawCircle(const Offset(18, height / 2 - 3), 4, iconSymbolPaint);
    }

    // Temperature text
    final tempParagraph = _createTextParagraph(
      '$temp°',
      18,
      FontWeight.bold,
      Colors.white,
      30,
    );
    canvas.drawParagraph(tempParagraph, const Offset(35, 6));

    // Visibility text (if available)
    if (visibility != null) {
      final visParagraph = _createTextParagraph(
        visibility,
        10,
        FontWeight.w500,
        const Color(0xFF8E8E93),
        40,
      );
      canvas.drawParagraph(visParagraph, const Offset(35, 30));
    }

    // Pointer at bottom
    final pointerPaint = Paint()
      ..color = isPassed
          ? const Color(0xFF4A4A4C)
          : isNext
              ? const Color(0xFF00C7BE)
              : const Color(0xFF2C2C2E)
      ..style = PaintingStyle.fill;
    final pointerPath = Path()
      ..moveTo(width / 2 - 8, height)
      ..lineTo(width / 2, height + 10)
      ..lineTo(width / 2 + 8, height)
      ..close();
    canvas.drawPath(pointerPath, pointerPaint);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(width.toInt(), (height + 12).toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    if (byteData != null) {
      return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  Paragraph _createTextParagraph(
    String text,
    double fontSize,
    FontWeight fontWeight,
    Color color,
    double width,
  ) {
    final builder = ParagraphBuilder(
      ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: fontSize,
      ),
    );
    builder.pushStyle(
      TextStyle(
        color: color,
        fontWeight: fontWeight,
        fontSize: fontSize,
      ).getTextStyle(),
    );
    builder.addText(text);
    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: width));
    return paragraph;
  }

  /// Get color for weather condition
  Color _getWeatherColor(String condition) {
    final lower = condition.toLowerCase();
    if (lower.contains('sun') || lower.contains('clear')) {
      return const Color(0xFFFFB800); // Sunny yellow
    } else if (lower.contains('rain') || lower.contains('drizzle')) {
      return const Color(0xFF007AFF); // Rain blue
    } else if (lower.contains('cloud') || lower.contains('overcast')) {
      return const Color(0xFF8E8E93); // Cloudy grey
    } else if (lower.contains('fog') || lower.contains('mist')) {
      return const Color(0xFFAFB1B3); // Fog grey
    } else if (lower.contains('thunder') || lower.contains('storm')) {
      return const Color(0xFF5856D6); // Storm purple
    } else if (lower.contains('snow')) {
      return const Color(0xFF87CEEB); // Snow light blue
    }
    return const Color(0xFFFF9500); // Default orange
  }

  /// Cache for weather card markers
  final Map<String, BitmapDescriptor> _weatherCardMarkerCache = {};

  /// Get or create weather card marker (with caching)
  Future<BitmapDescriptor> _getWeatherCardMarker({
    required int temp,
    required String condition,
    String? visibility,
    bool isNext = false,
    bool isPassed = false,
  }) async {
    final key = '${temp}_${condition}_${visibility ?? ''}_${isNext}_$isPassed';
    if (_weatherCardMarkerCache.containsKey(key)) {
      return _weatherCardMarkerCache[key]!;
    }
    final marker = await _createWeatherCardMarker(
      temp: temp,
      condition: condition,
      visibility: visibility,
      isNext: isNext,
      isPassed: isPassed,
    );
    _weatherCardMarkerCache[key] = marker;
    return marker;
  }

  /// Update weather card markers asynchronously
  Future<void> _updateWeatherCardMarkers() async {
    for (int i = 0; i < _routePoints.length; i++) {
      final tp = _routePoints[i];
      final isPassed = _isNavigating && i < _currentPointIndex;
      final isNext = _isNavigating && i == _currentPointIndex;

      // Skip passed points during navigation (except destination)
      if (isPassed && tp.point.type != PointType.destination) {
        continue;
      }

      // Get weather data
      final weather = tp.weather;
      final apiTemp = weather?.tempC.round() ?? 0;
      final apiCondition = weather?.condition ?? 'Unknown';

      // Get METAR data if available - only use if within airport radius (30km)
      final metar = _metarData[tp.point.id];
      final useMetar = _shouldUseMetar(metar);
      int temp = apiTemp;
      String condition = apiCondition;
      String? visibility;
      bool hasMetar = false;

      if (useMetar && metar != null) {
        hasMetar = true;

        // Use METAR temperature if available
        final metarTemp = _toDouble(metar['temp_c']);
        if (metarTemp != null) {
          temp = metarTemp.round();
        }

        // Extract visibility from visibility_km (already in km)
        final visKm = _toDouble(metar['visibility_km']);
        if (visKm != null) {
          visibility = '${visKm.toStringAsFixed(0)}km';
        }

        // Extract condition using same logic as main app
        if (metar['raw_text'] != null) {
          final code = _extractMetarCode(metar['raw_text'].toString());
          condition = mapMetarCodeToDescription(code);
        }
      }

      // Create weather card marker
      final markerIcon = await _getWeatherCardMarker(
        temp: temp,
        condition: condition,
        visibility: visibility,
        isNext: isNext,
        isPassed: isPassed,
      );

      _markers.add(
        Marker(
          markerId: MarkerId(tp.point.id),
          position: LatLng(tp.point.lat, tp.point.lon),
          icon: markerIcon,
          anchor: const Offset(0.5, 1.0), // Anchor at bottom center (pointer)
          alpha: isPassed ? 0.6 : 1.0,
          infoWindow: InfoWindow(
            title: tp.point.name,
            snippet:
                '${temp}°C - $condition${visibility != null ? ' • Vis: $visibility' : ''}${hasMetar ? ' (METAR)' : ''}',
          ),
          onTap: () => _showPointDetails(tp),
        ),
      );
    }
    // Trigger UI update after async marker creation
    if (mounted) setState(() {});
  }

  void _updateMapMarkers() {
    _markers.clear();
    _polylines.clear();

    // Add current location marker - uses smooth interpolated position
    if (_currentPosition != null) {
      // Use ticker-interpolated position for ultra-smooth display
      final markerLat = _displayLat != 0
          ? _displayLat
          : (_smoothedLat != 0 ? _smoothedLat : _currentPosition!.latitude);
      final markerLon = _displayLon != 0
          ? _displayLon
          : (_smoothedLon != 0 ? _smoothedLon : _currentPosition!.longitude);
      final displayPosition = LatLng(markerLat, markerLon);

      // Choose icon based on mode
      BitmapDescriptor markerIcon;

      if (_isNavigating) {
        // Always use navigation icon when navigating (regardless of speed)
        if (_useCarIcon && _carIcon != null) {
          markerIcon = _carIcon!;
        } else if (_navigationArrowIcon != null) {
          markerIcon = _navigationArrowIcon!;
        } else {
          markerIcon =
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
        }
      } else {
        // Not navigating - use blue dot
        markerIcon = _blueDotIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
      }

      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: displayPosition,
          icon: markerIcon,
          infoWindow: InfoWindow(
            title: _isNavigating ? '🚗 Navigating' : '📍 You',
            snippet: _isNavigating ? '${_currentSpeed.round()} km/h' : null,
          ),
          // Arrow rotates with smooth interpolated heading
          rotation: _isNavigating
              ? (_displayBearing != 0 ? _displayBearing : _smoothedBearing)
              : 0,
          anchor: const Offset(0.5, 0.5),
          flat:
              _isNavigating, // Flat when navigating - arrow points in direction of travel
          zIndex: 100,
        ),
      );
    }

    // Add route point markers with WEATHER CARD style
    // HIDE PASSED POINTS during navigation for cleaner view
    _updateWeatherCardMarkers();

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

  /// Filter points to only include toll plazas between user and destination
  /// Direction is determined by comparing user's distance to destination vs first point
  List<MotorwayPoint> _filterPointsOnRoute(
      List<MotorwayPoint> allPoints, String destinationId) {
    if (_currentPosition == null || allPoints.length < 2) return allPoints;

    final userLat = _currentPosition!.latitude;
    final userLon = _currentPosition!.longitude;

    // Find the actual destination point by ID
    final destIndex = allPoints.indexWhere((p) => p.id == destinationId);
    if (destIndex == -1) return allPoints;
    final destination = allPoints[destIndex];

    // Find which point the user is closest to
    int userNearestIndex = 0;
    double minDist = double.infinity;
    for (int i = 0; i < allPoints.length; i++) {
      final dist = Geolocator.distanceBetween(
          userLat, userLon, allPoints[i].lat, allPoints[i].lon);
      if (dist < minDist) {
        minDist = dist;
        userNearestIndex = i;
      }
    }

    // Determine travel direction based on user position vs destination
    // If destination index < user nearest index, we're going backward (towards start)
    // If destination index > user nearest index, we're going forward (towards end)
    final goingForward = destIndex > userNearestIndex;

    debugPrint(
        '🗺️ User nearest: ${allPoints[userNearestIndex].name} (idx $userNearestIndex), dest: ${destination.name} (idx $destIndex), goingForward=$goingForward');

    // Build the list of points between user and destination
    final pointsAhead = <MotorwayPoint>[];

    if (goingForward) {
      // Going forward (e.g., ISB to Lahore) - indices increasing
      // Find the first point user hasn't passed yet
      int startIndex = userNearestIndex;
      for (int i = userNearestIndex; i < destIndex; i++) {
        final currentPoint = allPoints[i];
        final nextPoint = allPoints[i + 1];
        final distToCurrent = Geolocator.distanceBetween(
            userLat, userLon, currentPoint.lat, currentPoint.lon);
        final distToNext = Geolocator.distanceBetween(
            userLat, userLon, nextPoint.lat, nextPoint.lon);
        if (distToNext < distToCurrent) {
          startIndex = i + 1;
        } else {
          break;
        }
      }

      // Include points from startIndex to destination (inclusive)
      for (int i = startIndex; i <= destIndex; i++) {
        pointsAhead.add(allPoints[i]);
      }
    } else {
      // Going backward (e.g., Lahore to ISB) - indices decreasing
      // Find the first point user hasn't passed yet
      int startIndex = userNearestIndex;
      for (int i = userNearestIndex; i > destIndex; i--) {
        final currentPoint = allPoints[i];
        final nextPoint = allPoints[i - 1];
        final distToCurrent = Geolocator.distanceBetween(
            userLat, userLon, currentPoint.lat, currentPoint.lon);
        final distToNext = Geolocator.distanceBetween(
            userLat, userLon, nextPoint.lat, nextPoint.lon);
        if (distToNext < distToCurrent) {
          startIndex = i - 1;
        } else {
          break;
        }
      }

      // Include points from startIndex down to destination (inclusive), in travel order
      for (int i = startIndex; i >= destIndex; i--) {
        pointsAhead.add(allPoints[i]);
      }
    }

    // If we filtered out everything, at least include destination
    if (pointsAhead.isEmpty) {
      pointsAhead.add(destination);
    }

    debugPrint(
        '🗺️ Filtered route: ${pointsAhead.length} points ahead (first: ${pointsAhead.first.name}, last: ${pointsAhead.last.name})');

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
      backgroundColor: _bgDark,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Stack(
            children: [
              // Main content column
              Column(
                children: [
                  // Apple-style header with From/To
                  _buildAppleStyleHeader(),
                  // Main content
                  Expanded(
                    child: _isLoading
                        ? _buildLoadingView()
                        : _error != null
                            ? _buildErrorView()
                            : _routeConfirmed
                                ? (_currentView == 0
                                    ? _buildAppleMapView()
                                    : _buildAppleTimelineView())
                                : _buildAppleRouteSelectionView(),
                  ),
                  // Bottom action bar (only after route confirmed)
                  if (_routeConfirmed && !_isNavigating) _buildAppleBottomBar(),
                ],
              ),
              // Search overlay for From location
              if (_showFromSearch)
                Positioned(
                  top: 60,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: _buildSearchOverlay(isFrom: true),
                  ),
                ),
              // Search overlay for To location
              if (_showToSearch)
                Positioned(
                  top: 100,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: _buildSearchOverlay(isFrom: false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Search overlay with list of toll plazas
  Widget _buildSearchOverlay({required bool isFrom}) {
    final controller = isFrom ? _fromSearchController : _toSearchController;
    final filteredPoints = _getFilteredPoints(controller.text);

    return Container(
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  isFrom ? Icons.trip_origin : Icons.location_on,
                  color: isFrom ? _accentBlue : _orangeAccent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: isFrom
                          ? 'Search starting point...'
                          : 'Search destination...',
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.4)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    if (isFrom) {
                      _showFromSearch = false;
                    } else {
                      _showToSearch = false;
                    }
                    controller.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        color: Colors.white54, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          // Current location option (only for From)
          if (isFrom)
            ListTile(
              dense: true,
              leading: Icon(Icons.my_location, color: _accentBlue, size: 22),
              title: const Text(
                'Current Location',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Use GPS',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 12),
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
          // List of toll plazas
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: filteredPoints.length,
              itemBuilder: (context, index) {
                final point = filteredPoints[index];
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _getPointColor(point.type).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getPointIcon(point.type),
                      color: _getPointColor(point.type),
                      size: 18,
                    ),
                  ),
                  title: Text(
                    point.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '${point.distanceFromStart.toStringAsFixed(0)} km from Islamabad',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withOpacity(0.3),
                    size: 14,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Apple-style header with From/To fields
  Widget _buildAppleStyleHeader() {
    final currentMotorway = PakistanMotorways.motorways
        .firstWhere((m) => m.id == _selectedMotorwayId);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: _bgDark,
        border: Border(
          bottom: BorderSide(color: _borderColor),
        ),
      ),
      child: Column(
        children: [
          // Top row: Back button, Motorway selector, Menu
          Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _cardDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              // Motorway selector chip
              Expanded(
                child: GestureDetector(
                  onTap: _showMotorwaySelectorSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _cardDark,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _orangeAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            currentMotorway.id.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentMotorway.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down,
                            color: Colors.white.withOpacity(0.6), size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Menu button
              GestureDetector(
                onTap: _showOptionsMenu,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _cardDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_vert,
                      color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // From field
          _buildLocationRow(
            label: 'A',
            value: _fromId == null
                ? 'Current Location'
                : _currentMotorwayPoints
                    .firstWhere((p) => p.id == _fromId,
                        orElse: () => _currentMotorwayPoints.first)
                    .name,
            isFrom: true,
            onTap: () => setState(() => _showFromSearch = true),
          ),
          const SizedBox(height: 4),
          // Divider with +Add Stops
          Row(
            children: [
              const SizedBox(width: 32),
              Expanded(
                child: Container(
                  height: 1,
                  color: _borderColor,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  // Future: Add stops functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Add stops coming soon')),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _cardDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '+ Add Stops',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // To field
          _buildLocationRow(
            label: 'B',
            value: _toId == null
                ? 'Choose Destination'
                : _currentMotorwayPoints
                    .firstWhere((p) => p.id == _toId,
                        orElse: () => _currentMotorwayPoints.last)
                    .name,
            isFrom: false,
            onTap: () => setState(() => _showToSearch = true),
          ),
          const SizedBox(height: 12),
          // Departure time row (simplified - removed non-functional elements)
          Row(
            children: [
              // Departure time - tappable with time picker
              GestureDetector(
                onTap: _showDepartureTimePicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _cardDark,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule,
                          color: Colors.white.withOpacity(0.6), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Departure: ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _getDepartureTimeText(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down,
                          color: Colors.white.withOpacity(0.6), size: 18),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Reset to Now button (only show if custom time is set)
              if (_departureTime != null)
                GestureDetector(
                  onTap: () {
                    setState(() => _departureTime = null);
                    if (_routeConfirmed) _loadRoute();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'Reset to Now',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required String label,
    required String value,
    required bool isFrom,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          // Label circle
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isFrom ? Colors.grey.shade600 : Colors.white,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: isFrom ? Colors.white : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: _toId == null && !isFrom ? Colors.white38 : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Apple-style bottom action bar
  Widget _buildAppleBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: _bgDark,
        border: Border(
          top: BorderSide(color: _borderColor),
        ),
      ),
      child: Row(
        children: [
          // Timeline button
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentView = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _currentView == 1 ? _cardDark : Colors.teal.shade800,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timeline, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Timeline',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Go Now button (orange)
          Expanded(
            child: GestureDetector(
              onTap: _startNavigation,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _orangeAccent,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.navigation, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Go Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // More menu
          GestureDetector(
            onTap: _showOptionsMenu,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardDark,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.more_horiz, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  /// Apple-style route selection view (before confirming route)
  Widget _buildAppleRouteSelectionView() {
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

    // Calculate total distance - use absolute difference for reverse direction
    final totalDistance = previewPoints.isNotEmpty
        ? (previewPoints.last.distanceFromStart -
                previewPoints.first.distanceFromStart)
            .abs()
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
                              mainAxisSize: MainAxisSize.min,
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

  // ignore: unused_element
  // ignore: unused_element
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
                _isNavigating ? 'Navigating' : 'Motorway Weather',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isNavigating)
                Text(
                  'Following your route',
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
// ignore: unused_element

  // ignore: unused_element
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
                    leading:
                        Icon(Icons.my_location, color: _accentBlue, size: 20),
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
    // ignore: unused_element
  }

  // ignore: unused_element
  Widget _buildViewToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDarkMode
            ? Colors.white.withOpacity(0.15)
            : _darkBlue.withOpacity(0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton(
              label: 'Map',
              icon: Icons.map_outlined,
              isActive: _currentView == 0,
              onTap: () {
                setState(() => _currentView = 0);
                // When switching to Map view during navigation, reset following
                if (_isNavigating && _currentPosition != null) {
                  _isFollowingUser = true;
                  // Restart map ticker to ensure smooth animation
                  _startMapTicker();
                  // Recenter on user after a small delay for map to render
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted && _isNavigating) {
                      _recenterOnUser(true);
                    }
                  });
                }
              },
            ),
          ),
          Expanded(
            child: _buildSegmentButton(
              label: 'Timeline',
              icon: Icons.view_timeline,
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
          color: isActive
              ? (_isDarkMode ? Colors.white : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
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
              color: isActive
                  ? (_isDarkMode ? _primaryBlue : _darkBlue)
                  : (_isDarkMode
                      ? Colors.white.withOpacity(0.8)
                      : Colors.white),
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? (_isDarkMode ? _primaryBlue : _darkBlue)
                    : (_isDarkMode
                        ? Colors.white.withOpacity(0.9)
                        : Colors.white),
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
      // ignore: unused_element
    );
  }

  // ignore: unused_element
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
    // Only use METAR if point is within range
    final metar = _getMetarIfInRange(tp.point.id);
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
                                        '${tp.distanceFromUser} km',
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
                        if (tp.nextPrayer != null) ...[
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

  /// Show motorway selector bottom sheet
  void _showMotorwaySelectorSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: _cardDark,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Motorway',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // Motorway list
            ...PakistanMotorways.motorways.map((motorway) => ListTile(
                  leading: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: motorway.id == _selectedMotorwayId
                          ? _orangeAccent
                          : motorway.isCombined
                              ? Colors.teal.withOpacity(0.2)
                              : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: motorway.isCombined
                          ? Border.all(color: Colors.teal, width: 1)
                          : null,
                    ),
                    child: Text(
                      motorway.isCombined ? 'M1+M2' : motorway.id.toUpperCase(),
                      style: TextStyle(
                        color: motorway.id == _selectedMotorwayId
                            ? Colors.white
                            : motorway.isCombined
                                ? Colors.teal
                                : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: motorway.isCombined ? 12 : 14,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        motorway.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (motorway.isCombined) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'FULL ROUTE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${motorway.subtitle} • ${motorway.distanceKm} km',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                  trailing: motorway.id == _selectedMotorwayId
                      ? const Icon(Icons.check_circle, color: _orangeAccent)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    if (motorway.id != _selectedMotorwayId) {
                      setState(() {
                        _selectedMotorwayId = motorway.id;
                        _fromId = null;
                        _toId = null;
                        _routePoints = [];
                        _roadRoutePoints = [];
                        _routeConfirmed = false;
                      });
                    }
                  },
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Show options menu
  void _showOptionsMenu() {
    final menuTextColor = _textColor;
    final menuSecondaryColor = _textSecondary;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: _cardDark,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: menuSecondaryColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // Menu items
            ListTile(
              leading: Icon(Icons.share, color: menuTextColor),
              title:
                  Text('Share Route', style: TextStyle(color: menuTextColor)),
              onTap: () {
                Navigator.pop(context);
                _shareRoute();
              },
            ),
            ListTile(
              leading: Icon(Icons.refresh, color: menuTextColor),
              title: Text('Refresh Weather',
                  style: TextStyle(color: menuTextColor)),
              onTap: () {
                Navigator.pop(context);
                if (_routeConfirmed) {
                  _loadRoute();
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.swap_vert, color: menuTextColor),
              title: Text('Swap Direction',
                  style: TextStyle(color: menuTextColor)),
              onTap: () {
                Navigator.pop(context);
                _swapDirection();
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline, color: menuTextColor),
              title: Text('Route Info', style: TextStyle(color: menuTextColor)),
              onTap: () {
                Navigator.pop(context);
                _showRouteInfo();
              },
            ),
            ListTile(
              leading: Icon(Icons.directions_car,
                  color: _useCarIcon ? _orangeAccent : menuTextColor),
              title: Text(
                _useCarIcon ? 'Switch to Arrow Icon' : 'Switch to Car Icon',
                style: TextStyle(color: menuTextColor),
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _useCarIcon = !_useCarIcon;
                });
                _updateMapMarkers();
              },
            ),
            ListTile(
              leading: Icon(
                _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: _isDarkMode ? _orangeAccent : menuTextColor,
              ),
              title: Text(
                _isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                style: TextStyle(color: menuTextColor),
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isDarkMode = !_isDarkMode;
                  _userThemeOverride = _isDarkMode; // User manually set theme
                });
                // Update map style when theme changes
                _mapController
                    ?.setMapStyle(_isDarkMode ? _darkMapStyle : _lightMapStyle);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Share route - copies to clipboard
  void _shareRoute() async {
    if (_routePoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No route to share')),
      );
      return;
    }

    final fromName = _fromId == null
        ? 'Current Location'
        : _currentMotorwayPoints.firstWhere((p) => p.id == _fromId).name;
    final toName = _currentMotorwayPoints.firstWhere((p) => p.id == _toId).name;
    final motorway = PakistanMotorways.motorways
        .firstWhere((m) => m.id == _selectedMotorwayId);

    final totalDist = _routeDistanceMeters > 0
        ? (_routeDistanceMeters / 1000).toStringAsFixed(0)
        : (_routePoints.isNotEmpty
            ? '${_routePoints.last.distanceFromUser}'
            : '0');

    final message = '''
🚗 Motorway Weather Route

📍 From: $fromName
📍 To: $toName
🛣️ Motorway: ${motorway.name}
📏 Distance: $totalDist km

Weather along route:
${_routePoints.take(5).map((tp) => '• ${tp.point.name}: ${tp.weather?.tempC.toStringAsFixed(0) ?? '--'}°C, ${tp.weather?.condition ?? 'N/A'}').join('\n')}

Shared via Weather Alert Pakistan
''';

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: message));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Route copied to clipboard!'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Get departure time display text
  String _getDepartureTimeText() {
    if (_departureTime == null) return 'Now';
    final now = DateTime.now();
    final diff = _departureTime!.difference(now);

    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes} min';

    final hour = _departureTime!.hour;
    final minute = _departureTime!.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Show departure time picker
  Future<void> _showDepartureTimePicker() async {
    final now = DateTime.now();
    final initialTime = _departureTime ?? now;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialTime),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Color(0xFF1C1C1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      // Create datetime with picked time
      DateTime newDeparture = DateTime(
        now.year,
        now.month,
        now.day,
        pickedTime.hour,
        pickedTime.minute,
      );

      // If picked time is in the past, assume tomorrow
      if (newDeparture.isBefore(now)) {
        newDeparture = newDeparture.add(const Duration(days: 1));
      }

      setState(() => _departureTime = newDeparture);

      // Reload route with new departure time
      if (_routeConfirmed) {
        _loadRoute();
      }
    }
  }

  /// Swap from/to direction
  void _swapDirection() {
    if (_toId == null) return;

    setState(() {
      final temp = _fromId;
      _fromId = _toId;
      _toId = temp;
    });

    if (_routeConfirmed) {
      _loadRoute();
    }
  }

  /// Show route info
  void _showRouteInfo() {
    if (_routePoints.isEmpty) return;

    final motorway = PakistanMotorways.motorways
        .firstWhere((m) => m.id == _selectedMotorwayId);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardDark,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              motorway.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              motorway.subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.straighten, 'Total Distance',
                '${_routeDistanceMeters > 0 ? (_routeDistanceMeters / 1000).toStringAsFixed(0) : motorway.distanceKm} km'),
            _buildInfoRow(
                Icons.schedule,
                'Estimated Time',
                _formatDuration(Duration(
                    seconds: _routeDurationSeconds > 0
                        ? _routeDurationSeconds
                        : (motorway.distanceKm * 0.6).toInt() * 60))),
            _buildInfoRow(Icons.location_on, 'Toll Plazas',
                '${_routePoints.where((p) => p.point.type == PointType.tollPlaza).length}'),
            _buildInfoRow(Icons.swap_horiz, 'Interchanges',
                '${_routePoints.where((p) => p.point.type == PointType.interchange).length}'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: _orangeAccent, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Check if a point is within METAR range based on stored distance/radius
  bool _isPointInMetarRange(String pointId) {
    final metar = _metarData[pointId];
    if (metar == null) return false;
    final distance = metar['_airport_distance_km'] as double?;
    final radius = metar['_airport_radius_km'] as double?;
    if (distance == null || radius == null) return false;
    return distance <= radius;
  }

  /// Get METAR data only if point is within range
  Map<String, dynamic>? _getMetarIfInRange(String pointId) {
    if (_isPointInMetarRange(pointId)) {
      return _metarData[pointId];
    }
    return null;
  }

  void _showPointDetails(TravelPoint tp) {
    // Only use METAR data if point is within METAR range
    final metar = _getMetarIfInRange(tp.point.id);

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
                        '${tp.distanceFromUser} km away',
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

  /// Apple Weather style map view with weather markers
  Widget _buildAppleMapView() {
    if (_routePoints.isEmpty) {
      return Center(
        child: Text(
          'Select a route to view on map',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      );
    }

    // Calculate center and bounds
    double centerLat = 0, centerLon = 0;
    for (final tp in _routePoints) {
      centerLat += tp.point.lat;
      centerLon += tp.point.lon;
    }
    centerLat /= _routePoints.length;
    centerLon /= _routePoints.length;

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
            markers: _buildAppleStyleMarkers(),
            polylines: {
              Polyline(
                polylineId: const PolylineId('route'),
                points: _roadRoutePoints.isNotEmpty
                    ? _roadRoutePoints
                    : _routePoints
                        .map((tp) => LatLng(tp.point.lat, tp.point.lon))
                        .toList(),
                color: _orangeAccent,
                width: 5,
              ),
            },
            onMapCreated: (controller) {
              _mapController = controller;
              // Set map style based on theme
              controller
                  .setMapStyle(_isDarkMode ? _darkMapStyle : _lightMapStyle);
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
            myLocationEnabled: !_isNavigating,
            myLocationButtonEnabled: false,
            compassEnabled: false,
          ),
        ),

        // Top right - Distance and time badge
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _routeDistanceMeters >= 1000
                      ? '${(_routeDistanceMeters / 1000).toStringAsFixed(0)} km'
                      : '$_routeDistanceMeters m',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatDuration(Duration(seconds: _routeDurationSeconds)),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Left side - Layer toggle button
        Positioned(
          top: 16,
          left: 16,
          child: GestureDetector(
            onTap: () => setState(() => _showLayerPicker = !_showLayerPicker),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getLayerIcon(_selectedMapLayer),
                      color: _getLayerColor(_selectedMapLayer), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _getLayerLabel(_selectedMapLayer),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _showLayerPicker
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Layer picker dropdown
        if (_showLayerPicker)
          Positioned(
            top: 60,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLayerOption(
                      'temp', Icons.thermostat, 'Temperature', Colors.orange),
                  _buildLayerOption(
                      'humidity', Icons.water_drop, 'Humidity', Colors.blue),
                  _buildLayerOption('visibility', Icons.visibility,
                      'Visibility', Colors.teal),
                  _buildLayerOption('wind', Icons.air, 'Wind', Colors.cyan),
                  _buildLayerOption(
                      'uv', Icons.wb_sunny, 'UV Index', Colors.amber),
                ],
              ),
            ),
          ),

        // Speedometer widget (when navigating) - Bottom Left above green button
        if (_isNavigating)
          Positioned(
            bottom: 100, // Just above the green slider button
            left: 16,
            child: _buildSpeedometerWidget(),
          ),

        // Next toll plaza weather card (when navigating)
        if (_isNavigating)
          Positioned(
            top: 100,
            right: 16,
            left: 16,
            child: _buildNextTollPlazaCard(),
          ),

        // Recenter Button - Always visible above Start/Stop button
        if (!_showTimelineSlider)
          Positioned(
            bottom: 145,
            right: 16,
            child: GestureDetector(
              onTap: () => _recenterOnUser(true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isFollowingUser ? Colors.green : _orangeAccent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: (_isFollowingUser ? Colors.green : _orangeAccent)
                          .withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isFollowingUser ? Icons.gps_fixed : Icons.my_location,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isFollowingUser ? 'Following' : 'Recenter',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Start/Stop Journey button
        if (!_showTimelineSlider)
          Positioned(
            bottom: 80,
            right: 16,
            child: GestureDetector(
              onTap: _isNavigating ? _stopNavigation : _startNavigation,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: _isNavigating
                      ? Colors.red.shade600
                      : Colors.green.shade600,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (_isNavigating ? Colors.red : Colors.green)
                          .withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isNavigating ? Icons.stop : Icons.navigation,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isNavigating ? 'Stop' : 'Start Journey',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Bottom left - Timeline slider button (GREEN)
        Positioned(
          bottom: _showTimelineSlider ? 200 : 16,
          left: 16,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showTimelineSlider = !_showTimelineSlider;
                if (_showTimelineSlider) {
                  _sliderValue = 0.0;
                  _sliderPointIndex = 0;
                } else {
                  _stopSliderPlayback();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _showTimelineSlider
                    ? Colors.green.shade700
                    : Colors.green.shade600,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timeline, color: Colors.white, size: 24),
                  if (_showTimelineSlider) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Bottom right - Timeline list view button
        if (!_showTimelineSlider)
          Positioned(
            bottom: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => setState(() => _currentView = 1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _cardDark,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.list, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Timeline',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Timeline slider overlay
        if (_showTimelineSlider) _buildTimelineSliderOverlay(),
      ],
    );
  }

  /// Build the timeline slider overlay at bottom of map
  Widget _buildTimelineSliderOverlay() {
    if (_routePoints.isEmpty) return const SizedBox.shrink();

    // Get current point based on slider
    final currentPoint = _routePoints[_sliderPointIndex];
    final weather = currentPoint.weather;
    // Only use METAR if point is within range
    final metar = _getMetarIfInRange(currentPoint.point.id);
    final useMetar = _shouldUseMetar(metar);

    // API fallback values
    final apiTemp = weather?.tempC.round() ?? 0;
    final apiCondition = weather?.condition ?? 'N/A';
    final apiHumidity = weather?.humidity.round() ?? 0;
    final apiWindKph = weather?.windKph.round() ?? 0;
    final chanceOfRain = weather?.rainChance?.round() ?? 0;

    // Prefer METAR values when within airport radius (30km)
    int temp = apiTemp;
    String condition = apiCondition;
    int humidity = apiHumidity;
    int windKph = apiWindKph;
    String? metarVisibility;
    bool hasMetar = false;

    if (useMetar && metar != null) {
      hasMetar = true;

      // Use METAR temperature if available
      final metarTemp = _toDouble(metar['temp_c']);
      if (metarTemp != null) {
        temp = metarTemp.round();
      }

      // Use METAR humidity if available
      final metarHumidity = _toDouble(metar['humidity']);
      if (metarHumidity != null) {
        humidity = metarHumidity.round();
      }

      // Use METAR wind if available
      final metarWind = _toDouble(metar['wind_kph']);
      if (metarWind != null) {
        windKph = metarWind.round();
      }

      // Extract visibility from visibility_km (already in km)
      final visKm = _toDouble(metar['visibility_km']);
      if (visKm != null) {
        metarVisibility = '${visKm.toStringAsFixed(1)} km';
      }

      // Extract condition using same logic as main app
      if (metar['raw_text'] != null) {
        final code = _extractMetarCode(metar['raw_text'].toString());
        condition = mapMetarCodeToDescription(code);
      }
    }

    final arrivalTime = currentPoint.estimatedArrival;
    final timeStr = arrivalTime != null
        ? '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Stack(
      children: [
        // Close button - Top right of slider overlay
        Positioned(
          top: 10,
          right: 16,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showTimelineSlider = false;
                _stopSliderPlayback();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _cardDark,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                  Colors.black.withOpacity(0.95),
                ],
                stops: const [0.0, 0.2, 1.0],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 30),
                // Weather info card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _cardDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      // Location and time
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentPoint.point.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.access_time,
                                        color: Colors.white.withOpacity(0.6),
                                        size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Arrival: $timeStr',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(Icons.straighten,
                                        color: Colors.white.withOpacity(0.6),
                                        size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${currentPoint.distanceFromUser} km',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Temperature
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$temp°',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    condition.length > 18
                                        ? '${condition.substring(0, 18)}...'
                                        : condition,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (hasMetar) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'METAR',
                                        style: TextStyle(
                                          color: Colors.blue,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              // METAR visibility
                              if (metarVisibility != null) ...[
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.visibility,
                                        color: Colors.teal.withOpacity(0.7),
                                        size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Vis: $metarVisibility',
                                      style: TextStyle(
                                          color: Colors.teal.withOpacity(0.8),
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Weather details row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildWeatherDetail(
                              Icons.water_drop, '$chanceOfRain%', 'Rain'),
                          Container(
                              width: 1, height: 30, color: Colors.white24),
                          _buildWeatherDetail(
                              Icons.opacity, '$humidity%', 'Humidity'),
                          Container(
                              width: 1, height: 30, color: Colors.white24),
                          _buildWeatherDetail(
                              Icons.air, '$windKph km/h', 'Wind'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Slider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Progress indicator (location dots)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          min(_routePoints.length, 10),
                          (index) {
                            final actualIndex =
                                (index * (_routePoints.length - 1) / 9).round();
                            final isActive = actualIndex <= _sliderPointIndex;
                            final isCurrent = actualIndex == _sliderPointIndex;
                            return Container(
                              width: isCurrent ? 12 : 8,
                              height: isCurrent ? 12 : 8,
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green : Colors.white24,
                                shape: BoxShape.circle,
                                border: isCurrent
                                    ? Border.all(color: Colors.white, width: 2)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.green,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 10),
                          trackHeight: 6,
                          overlayColor: Colors.green.withOpacity(0.2),
                        ),
                        child: Slider(
                          value: _sliderValue,
                          min: 0,
                          max: 1,
                          onChanged: (value) {
                            setState(() {
                              _sliderValue = value;
                              _sliderPointIndex =
                                  (value * (_routePoints.length - 1)).round();
                            });
                            // Move map camera to current point
                            final point = _routePoints[_sliderPointIndex];
                            _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(
                                LatLng(point.point.lat, point.point.lon),
                                12,
                              ),
                            );
                          },
                        ),
                      ),
                      // Start and end labels
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _routePoints.first.point.name,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Play/Pause button
                            GestureDetector(
                              onTap: _toggleSliderPlayback,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _isSliderPlaying
                                      ? Colors.red
                                      : Colors.green,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isSliderPlaying
                                              ? Colors.red
                                              : Colors.green)
                                          .withOpacity(0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isSliderPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _routePoints.last.point.name,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.end,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Toggle slider auto-playback
  void _toggleSliderPlayback() {
    if (_isSliderPlaying) {
      _stopSliderPlayback();
    } else {
      _startSliderPlayback();
    }
  }

  /// Start auto-playing through route points
  void _startSliderPlayback() {
    if (_routePoints.isEmpty) return;

    // Reset to start if at end
    if (_sliderPointIndex >= _routePoints.length - 1) {
      setState(() {
        _sliderValue = 0.0;
        _sliderPointIndex = 0;
      });
    }

    setState(() => _isSliderPlaying = true);

    // Advance every 1.5 seconds
    _sliderPlayTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!mounted || !_isSliderPlaying) {
        timer.cancel();
        return;
      }

      setState(() {
        _sliderPointIndex++;
        if (_sliderPointIndex >= _routePoints.length) {
          _sliderPointIndex = _routePoints.length - 1;
          _stopSliderPlayback();
          return;
        }
        _sliderValue = _sliderPointIndex / (_routePoints.length - 1);
      });

      // Move map camera
      final point = _routePoints[_sliderPointIndex];
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(point.point.lat, point.point.lon),
          12,
        ),
      );
    });
  }

  /// Stop auto-playback
  void _stopSliderPlayback() {
    _sliderPlayTimer?.cancel();
    _sliderPlayTimer = null;
    if (mounted) {
      setState(() => _isSliderPlaying = false);
    }
  }

  Widget _buildWeatherDetail(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.7), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// Build layer option for dropdown
  Widget _buildLayerOption(
      String id, IconData icon, String label, Color color) {
    final isSelected = _selectedMapLayer == id;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMapLayer = id;
          _showLayerPicker = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.white70, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, color: color, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getLayerIcon(String layer) {
    switch (layer) {
      case 'temp':
        return Icons.thermostat;
      case 'humidity':
        return Icons.water_drop;
      case 'visibility':
        return Icons.visibility;
      case 'wind':
        return Icons.air;
      case 'uv':
        return Icons.wb_sunny;
      default:
        return Icons.thermostat;
    }
  }

  Color _getLayerColor(String layer) {
    switch (layer) {
      case 'temp':
        return Colors.orange;
      case 'humidity':
        return Colors.blue;
      case 'visibility':
        return Colors.teal;
      case 'wind':
        return Colors.cyan;
      case 'uv':
        return Colors.amber;
      default:
        return Colors.orange;
    }
  }

  String _getLayerLabel(String layer) {
    switch (layer) {
      case 'temp':
        return 'Temp';
      case 'humidity':
        return 'Humidity';
      case 'visibility':
        return 'Visibility';
      case 'wind':
        return 'Wind';
      case 'uv':
        return 'UV';
      default:
        return 'Temp';
    }
  }

  /// Speedometer widget - circular style
  Widget _buildSpeedometerWidget() {
    final speed = _currentSpeed.round();
    final isOverSpeed = speed > 120; // Motorway limit typically 120 km/h

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _cardDark,
        border: Border.all(
          color: isOverSpeed ? Colors.red : _orangeAccent,
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOverSpeed ? Colors.red : _orangeAccent).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$speed',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isOverSpeed ? Colors.red : Colors.white,
            ),
          ),
          Text(
            'km/h',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isOverSpeed ? Colors.red.shade300 : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  /// Next toll plaza weather card
  Widget _buildNextTollPlazaCard() {
    if (_routePoints.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Loading route...',
            style: TextStyle(color: Colors.white)),
      );
    }

    // Check if user has arrived at destination
    if (_hasArrived) {
      final destination = _routePoints.last.point.name;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green, width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You have arrived!',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    destination,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Find the next toll plaza (interchanges are also toll plazas in Pakistan)
    // Start from _currentPointIndex (the point we're heading towards)
    // This includes the current target if it's a toll plaza
    TravelPoint? nextTollPlaza;
    for (int i = _currentPointIndex; i < _routePoints.length; i++) {
      final pointType = _routePoints[i].point.type;
      // Toll plazas and interchanges both have toll collection
      if (pointType == PointType.tollPlaza ||
          pointType == PointType.interchange) {
        nextTollPlaza = _routePoints[i];
        break;
      }
    }

    // If no toll plaza ahead, show destination message
    if (nextTollPlaza == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('No toll plaza ahead',
            style: TextStyle(color: Colors.white)),
      );
    }

    final nextPoint = nextTollPlaza;
    final weather = nextPoint.weather;
    // Only use METAR if point is within range
    final metar = _getMetarIfInRange(nextPoint.point.id);

    // Prayer time info (reserved for future use)
    // ignore: unused_local_variable
    final prayerName = nextPoint.nextPrayer;
    // ignore: unused_local_variable
    final prayerTime = nextPoint.nextPrayerTime;

    // Calculate distance to next point
    double distanceToNext = 0;
    if (_currentPosition != null) {
      distanceToNext = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            nextPoint.point.lat,
            nextPoint.point.lon,
          ) /
          1000; // Convert to km
    }

    // API fallback values
    final apiTemp = weather?.tempC.round() ?? 0;
    final apiCondition = weather?.condition ?? 'N/A';
    final apiHumidity = weather?.humidity ?? 0;
    final apiWindKph = weather?.windKph.round() ?? 0;

    // Prefer METAR values when within airport radius (30km)
    final useMetar = _shouldUseMetar(metar);
    int temp = apiTemp;
    String displayCondition = apiCondition;
    int humidity = apiHumidity;
    int windKph = apiWindKph;
    String? visibility;
    bool hasMetar = false;

    if (useMetar && metar != null) {
      hasMetar = true;

      // Use METAR temperature if available
      final metarTemp = _toDouble(metar['temp_c']);
      if (metarTemp != null) {
        temp = metarTemp.round();
      }

      // Use METAR humidity if available
      final metarHumidity = _toDouble(metar['humidity']);
      if (metarHumidity != null) {
        humidity = metarHumidity.round();
      }

      // Use METAR wind if available
      final metarWind = _toDouble(metar['wind_kph']);
      if (metarWind != null) {
        windKph = metarWind.round();
      }

      // Extract visibility from visibility_km (already in km)
      final visKm = _toDouble(metar['visibility_km']);
      if (visKm != null) {
        visibility = visKm.toStringAsFixed(1);
      }

      // Extract condition using same logic as main app
      if (metar['raw_text'] != null) {
        final code = _extractMetarCode(metar['raw_text'].toString());
        displayCondition = mapMetarCodeToDescription(code);
      }
    }

    final feelsLike = temp; // Use METAR temp or fallback

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardDark.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _orangeAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _orangeAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'NEXT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nextPoint.point.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${distanceToNext.toStringAsFixed(1)} km',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Weather row
          Row(
            children: [
              // Temperature and condition
              Icon(
                _getWeatherIconFromCondition(displayCondition,
                    isDay: weather?.isDay ?? true),
                color: (weather?.isDay ?? true)
                    ? Colors.amber
                    : Colors.blueGrey.shade200,
                size: 32,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$temp°C',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayCondition.length > 25
                            ? '${displayCondition.substring(0, 25)}...'
                            : displayCondition,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                      if (hasMetar) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'METAR',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const Spacer(),
              // Weather details
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.thermostat,
                          color: Colors.orange.withOpacity(0.7), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Feels $feelsLike°',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.water_drop,
                          color: Colors.blue.withOpacity(0.7), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '$humidity%',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.air,
                          color: Colors.cyan.withOpacity(0.7), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '$windKph km/h',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 11),
                      ),
                    ],
                  ),
                  if (visibility != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility,
                            color: Colors.teal.withOpacity(0.7), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '$visibility km',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'METAR',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 8,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
          // Current prayer time with countdown (not "at arrival")
          if (_currentPrayerName != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _orangeAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _orangeAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.mosque, color: _orangeAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _currentPrayerName!,
                    style: TextStyle(
                      color: _orangeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _getPrayerCountdown(),
                    style: TextStyle(
                      color: _orangeAccent.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Set<Marker> _buildAppleStyleMarkers() {
    final markers = <Marker>{};

    // Add current location marker when navigating
    if (_isNavigating && _currentPosition != null) {
      // Use smooth interpolated position for display
      final markerLat = _displayLat != 0
          ? _displayLat
          : (_smoothedLat != 0 ? _smoothedLat : _currentPosition!.latitude);
      final markerLon = _displayLon != 0
          ? _displayLon
          : (_smoothedLon != 0 ? _smoothedLon : _currentPosition!.longitude);
      final displayPosition = LatLng(markerLat, markerLon);

      // Choose icon - car or arrow
      BitmapDescriptor markerIcon;
      if (_useCarIcon && _carIcon != null) {
        markerIcon = _carIcon!;
      } else if (_navigationArrowIcon != null) {
        markerIcon = _navigationArrowIcon!;
      } else {
        markerIcon =
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      }

      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: displayPosition,
          icon: markerIcon,
          infoWindow: InfoWindow(
            title: '🚗 Navigating',
            snippet: '${_currentSpeed.round()} km/h',
          ),
          rotation: _displayBearing != 0 ? _displayBearing : _smoothedBearing,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndex: 100,
        ),
      );
    }

    for (int i = 0; i < _routePoints.length; i++) {
      final tp = _routePoints[i];
      final weather = tp.weather;
      if (weather == null) continue;

      final temp = weather.tempC.round();
      // Only use METAR if point is within range
      final metar = _getMetarIfInRange(tp.point.id);
      final visibility = metar?['visibility']?['meters'] != null
          ? '${(metar!['visibility']['meters'] / 1000).toStringAsFixed(0)}km'
          : null;

      markers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: LatLng(tp.point.lat, tp.point.lon),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: '${tp.point.name} - $temp°',
            snippet:
                '${weather.condition}${visibility != null ? ' • Vis: $visibility' : ''}',
          ),
          onTap: () => _showPointDetails(tp),
        ),
      );
    }

    return markers;
  }

  /// Apple Weather style timeline view
  Widget _buildAppleTimelineView() {
    if (_routePoints.isEmpty) {
      return Center(
        child: Text(
          'No route data available',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      );
    }

    // Filter to only show upcoming points (not passed) during navigation
    // Keep all points when not navigating
    final displayPoints = _isNavigating
        ? _routePoints
            .asMap()
            .entries
            .where((e) =>
                e.key >= _confirmedPointIndex ||
                e.value.point.type == PointType.destination)
            .map((e) => MapEntry(e.key, e.value))
            .toList()
        : _routePoints.asMap().entries.toList();

    // Get the starting point name (first upcoming point or current location)
    final startingPointName = _isNavigating && _currentPosition != null
        ? 'Your Location'
        : _routePoints.first.point.name;

    return Container(
      color: _bgDark,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (_isNavigating)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${displayPoints.length} stops ahead',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                const Spacer(),
                Text(
                  'Tap section for more details',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.ios_share, color: Colors.white),
                  onPressed: _shareRoute,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    setState(() => _currentView = 0);
                    // When switching to Map view during navigation, reset following
                    if (_isNavigating && _currentPosition != null) {
                      _isFollowingUser = true;
                      _startMapTicker();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted && _isNavigating) {
                          _recenterOnUser(true);
                        }
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          // Starting city
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              startingPointName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Timeline list - only show upcoming points
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: displayPoints.length,
              itemBuilder: (context, displayIndex) {
                final entry = displayPoints[displayIndex];
                final tp = entry.value;
                final originalIndex = entry.key;
                final isNext = originalIndex == _confirmedPointIndex;
                return _buildAppleTimelineItem(tp, originalIndex, isNext);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppleTimelineItem(TravelPoint tp, int index,
      [bool isNext = false]) {
    final weather = tp.weather;
    // Only use METAR if point is within range
    final metar = _getMetarIfInRange(tp.point.id);
    final useMetar = _shouldUseMetar(metar);
    final apiTemp = weather?.tempC.round() ?? 0;
    final apiCondition = weather?.condition ?? '';
    final chanceOfRain = weather?.rainChance?.round() ?? 0;
    final prayerName = tp.nextPrayer;
    final prayerTime = tp.nextPrayerTime;

    // Dynamic distance calculation during navigation:
    // - GPS distance to NEXT plaza (real-time as you approach)
    // - Plus road distance from next plaza to subsequent plazas
    double dynamicDistanceKm = tp.distanceFromUser.toDouble();

    if (_isNavigating && _currentPosition != null && _routePoints.isNotEmpty) {
      // Get the next plaza we're tracking (current index)
      final nextPlazaIndex = _confirmedPointIndex < _routePoints.length
          ? _confirmedPointIndex
          : _routePoints.length - 1;
      final nextPlaza = _routePoints[nextPlazaIndex];

      // GPS distance from current position to NEXT plaza (real-time)
      final gpsToNextPlaza = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            nextPlaza.point.lat,
            nextPlaza.point.lon,
          ) /
          1000; // meters to km

      if (index == nextPlazaIndex) {
        // This IS the next plaza - show real-time GPS distance
        dynamicDistanceKm = gpsToNextPlaza;
      } else if (index > nextPlazaIndex) {
        // This is BEYOND the next plaza - GPS to next + road distance between plazas
        final roadDistBetween =
            (tp.point.distanceFromStart - nextPlaza.point.distanceFromStart)
                .abs();
        dynamicDistanceKm = gpsToNextPlaza + roadDistBetween;
      }
      // For passed plazas (index < nextPlazaIndex), keep original distance (they're behind us)
    }

    // Get METAR data if within airport radius (30km)
    int temp = apiTemp;
    String condition = apiCondition;
    String? metarVisibility;
    bool hasMetar = false;

    if (useMetar && metar != null) {
      hasMetar = true;

      // Use METAR temperature if available
      final metarTemp = _toDouble(metar['temp_c']);
      if (metarTemp != null) {
        temp = metarTemp.round();
      }

      // Extract visibility from visibility_km (already in km)
      final visKm = _toDouble(metar['visibility_km']);
      if (visKm != null) {
        metarVisibility = '${visKm.toStringAsFixed(1)} km';
      }

      // Extract condition using same logic as main app
      if (metar['raw_text'] != null) {
        final code = _extractMetarCode(metar['raw_text'].toString());
        condition = mapMetarCodeToDescription(code);
      }
    }

    final time = tp.estimatedArrival != null
        ? '${tp.estimatedArrival!.hour}:${tp.estimatedArrival!.minute.toString().padLeft(2, '0')} ${tp.estimatedArrival!.hour < 12 ? 'AM' : 'PM'}'
        : '--:--';

    // Use dynamic distance for real-time updates
    final distanceDisplay = dynamicDistanceKm < 1
        ? '${(dynamicDistanceKm * 1000).toStringAsFixed(0)} m'
        : '${dynamicDistanceKm.toStringAsFixed(1)} km';

    return GestureDetector(
      onTap: () => _showPointDetails(tp),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isNext ? _orangeAccent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isNext
              ? Border.all(color: _orangeAccent.withOpacity(0.5), width: 1)
              : null,
        ),
        child: Row(
          children: [
            // "NEXT" badge for upcoming point
            if (isNext) ...[
              Container(
                width: 6,
                height: 60,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _orangeAccent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
            // Weather icon
            SizedBox(
              width: isNext ? 54 : 60,
              child: Column(
                children: [
                  Icon(
                    _getWeatherIconFromCondition(condition,
                        isDay: _isDayAtTime(tp.estimatedArrival)),
                    color: isNext
                        ? _orangeAccent
                        : (_isDayAtTime(tp.estimatedArrival)
                            ? Colors.white
                            : Colors.blueGrey.shade200),
                    size: 36,
                  ),
                  if (chanceOfRain > 0)
                    Text(
                      '$chanceOfRain%',
                      style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            // Time and location
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tp.point.name,
                          style: TextStyle(
                            color: isNext ? _orangeAccent : Colors.white,
                            fontSize: isNext ? 15 : 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isNext)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _orangeAccent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEXT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        ' • $distanceDisplay',
                        style: TextStyle(
                          color: isNext
                              ? _orangeAccent.withOpacity(0.8)
                              : Colors.white.withOpacity(0.5),
                          fontSize: 12,
                          fontWeight:
                              isNext ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  if (prayerName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.mosque, color: _orangeAccent, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '$prayerName${prayerTime != null ? ' $prayerTime' : ''}',
                          style: TextStyle(
                            color: _orangeAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Timeline dot - highlight next point
            Container(
              width: isNext ? 14 : 10,
              height: isNext ? 14 : 10,
              decoration: BoxDecoration(
                color: isNext ? _orangeAccent : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                    color: isNext ? _orangeAccent : Colors.white, width: 2),
                boxShadow: isNext
                    ? [
                        BoxShadow(
                            color: _orangeAccent.withOpacity(0.5),
                            blurRadius: 8)
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            // Temperature
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$temp°',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                if (condition.isNotEmpty)
                  Text(
                    condition.length > 20
                        ? '${condition.substring(0, 20)}...'
                        : condition,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                // METAR visibility and badge
                if (hasMetar) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (metarVisibility != null) ...[
                        Icon(Icons.visibility,
                            color: Colors.teal.withOpacity(0.7), size: 10),
                        const SizedBox(width: 2),
                        Text(
                          metarVisibility,
                          style: TextStyle(
                              color: Colors.teal.withOpacity(0.8),
                              fontSize: 10),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'METAR',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Check if a given time is during daytime (6 AM to 6 PM roughly)
  /// Used for weather icon display based on estimated arrival time
  /// If no time provided, uses current time
  bool _isDayAtTime([DateTime? time]) {
    final checkTime = time ?? DateTime.now();
    final hour = checkTime.hour;
    // Day time is roughly 6 AM to 6 PM in Pakistan
    return hour >= 6 && hour < 18;
  }

  IconData _getWeatherIconFromCondition(String condition, {bool isDay = true}) {
    final lower = condition.toLowerCase();

    // Clear/sunny conditions - use moon at night
    if (lower.contains('sunny') || lower.contains('clear')) {
      return isDay ? Icons.wb_sunny : Icons.nightlight_round;
    }

    // Partly cloudy - use night variant
    if (lower.contains('partly')) {
      return isDay ? Icons.wb_cloudy : Icons.nights_stay;
    }

    if (lower.contains('cloud') || lower.contains('overcast'))
      return Icons.cloud;
    if (lower.contains('rain') || lower.contains('drizzle')) return Icons.grain;
    if (lower.contains('snow') || lower.contains('sleet')) return Icons.ac_unit;
    if (lower.contains('thunder') || lower.contains('storm'))
      return Icons.flash_on;
    if (lower.contains('fog') || lower.contains('mist')) return Icons.blur_on;
    if (lower.contains('wind')) return Icons.air;

    // Default - use moon at night for generic cloud
    return isDay ? Icons.cloud : Icons.nights_stay;
  }

  // ignore: unused_element
  int _getIconCodeFromCondition(String condition) {
    final lower = condition.toLowerCase();
    if (lower.contains('sunny') || lower.contains('clear')) return 1000;
    if (lower.contains('partly')) return 1003;
    if (lower.contains('cloud') || lower.contains('overcast')) return 1006;
    if (lower.contains('rain')) return 1063;
    if (lower.contains('snow')) return 1210;
    if (lower.contains('thunder')) return 1273;
    return 1000;
  }

  // Dark map style JSON
  static const String _darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#242f3e"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#746855"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#242f3e"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#38414e"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212a37"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#746855"}]},
  // ignore: unused_element
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17263c"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#515c6d"}]}
]
''';

  // Light map style JSON - clean minimal style
  static const String _lightMapStyle = '''
[
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit", "elementType": "labels", "stylers": [{"visibility": "off"}]}
]
''';

  // ignore: unused_element
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
            // Disable built-in my location when navigating (we draw our own custom marker)
            myLocationEnabled: !_isNavigating,
            myLocationButtonEnabled: false,
            compassEnabled: true, // Enable compass
            onCameraMove: (_) {
              // Only stop following if user is manually moving (not programmatic)
              if (_isNavigating &&
                  _isFollowingUser &&
                  !_isProgrammaticCameraMove) {
                setState(() => _isFollowingUser = false);
              }
            },
          ),
        ),

        // Off-route warning banner
        if (_isNavigating && _isOffRoute)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade700,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Off route - Recalculating...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Weather Card Overlay - Top Left (always visible)
        Positioned(
          top: _isOffRoute ? 50 : 16,
          left: 16,
          right: 80, // Leave room for compass button on right
          child: _buildMapWeatherCard(),
        ),

        // Layer Picker Button - Below weather card
        Positioned(
          top: _isOffRoute ? 140 : 100,
          left: 16,
          child: _buildLayerPickerButton(),
        ),

        // Next Toll Plaza Card - During Navigation
        if (_isNavigating)
          Positioned(
            top: _isOffRoute ? 200 : 150,
            left: 16,
            right: 16,
            child: _buildNextTollPlazaCard(),
          ),

        // Route Info Card - Bottom (always visible)
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: _buildRouteInfoCard(),
        ),

        // Recenter Button - Above the route info card
        Positioned(
          bottom: 200,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _recenterOnUser(true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _isFollowingUser ? Colors.green : _orangeAccent,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: (_isFollowingUser ? Colors.green : _orangeAccent)
                          .withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isFollowingUser ? Icons.gps_fixed : Icons.my_location,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isFollowingUser ? 'Following' : 'Recenter',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // START/STOP Navigation Button - Bottom Center
        Positioned(
          bottom: 145,
          left: 0,
          right: 0,
          child: Center(
            child: _buildStartStopButton(),
          ),
        ),

        // Off-route warning indicator
        if (_isNavigating && _isOffRoute)
          Positioned(
            top: 130,
            left: 16,
            right: 16,
            child: _buildOffRouteWarning(),
          ),

        // Compass Button - Top Right (rotates to show north)
        Positioned(
          top: 16,
          right: 16,
          child: _buildCompassButton(),
        ),

        // Location/Recenter Button - Bottom Right
        Positioned(
          bottom: 200, // Moved up to avoid overlap with route info card
          right: 16,
          child: _buildMapButton(
            // Show different icon based on state:
            // - Not navigating: my_location (current location)
            // - Navigating + following: navigation (compass mode active)
            // - Navigating + not following: gps_fixed (recenter)
            icon: !_isNavigating
                ? Icons.my_location
                : (_isFollowingUser ? Icons.navigation : Icons.gps_fixed),
            onTap: () => _recenterOnUser(false),
            onDoubleTap: () =>
                _recenterOnUser(true), // Double-tap to recenter with heading
          ),
        ),

        // Zoom Controls - Bottom Right
        Positioned(
          bottom: 260, // Moved up
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
            bottom: 360, // Moved up
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

  /// Build compass button that rotates to show north
  Widget _buildCompassButton() {
    // Calculate compass rotation - rotate opposite to current bearing
    final compassRotation =
        -(_roadBearing != 0 ? _roadBearing : _currentHeading);

    return GestureDetector(
      onTap: () {
        // Reset map rotation to north
        if (_mapController != null && _currentPosition != null && mounted) {
          try {
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude),
                  zoom: _isNavigating ? 18 : 14,
                  bearing: 0, // North up
                  tilt: _isNavigating ? 45 : 0,
                ),
              ),
            );
          } catch (e) {
            debugPrint('⚠️ Compass camera error: $e');
          }
        }
      },
      child: Container(
        width: 50,
        height: 50,
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
        child: Transform.rotate(
          angle: compassRotation * (3.14159265359 / 180),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // North indicator (red)
              Positioned(
                top: 6,
                child: Container(
                  width: 8,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ),
              // South indicator (white/grey)
              Positioned(
                bottom: 6,
                child: Container(
                  width: 8,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(4)),
                  ),
                ),
              ),
              // Center dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _primaryBlue,
                  shape: BoxShape.circle,
                ),
              ),
              // N label
              Positioned(
                top: 2,
                child: Text(
                  'N',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build off-route warning card
  Widget _buildOffRouteWarning() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade700,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Off Route',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Recalculating...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton(
      {required IconData icon,
      required VoidCallback onTap,
      VoidCallback? onDoubleTap}) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
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

  /// Layer picker button with dropdown for selecting weather layer
  Widget _buildLayerPickerButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main button
        GestureDetector(
          onTap: () {
            setState(() {
              _showLayerPicker = !_showLayerPicker;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getLayerIcon(_selectedMapLayer),
                    color: _getLayerColor(_selectedMapLayer), size: 18),
                const SizedBox(width: 6),
                Text(
                  _getLayerLabel(_selectedMapLayer),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showLayerPicker
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        ),

        // Dropdown options
        if (_showLayerPicker)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLayerOption('temp', _getLayerIcon('temp'),
                    _getLayerLabel('temp'), _getLayerColor('temp')),
                _buildLayerOption('humidity', _getLayerIcon('humidity'),
                    _getLayerLabel('humidity'), _getLayerColor('humidity')),
                _buildLayerOption('visibility', _getLayerIcon('visibility'),
                    _getLayerLabel('visibility'), _getLayerColor('visibility')),
                _buildLayerOption('wind', _getLayerIcon('wind'),
                    _getLayerLabel('wind'), _getLayerColor('wind')),
                _buildLayerOption('uv', _getLayerIcon('uv'),
                    _getLayerLabel('uv'), _getLayerColor('uv')),
              ],
            ),
          ),
      ],
    );
  }

  /// Start/Stop Navigation button
  Widget _buildStartStopButton() {
    return GestureDetector(
      onTap: () {
        if (_isNavigating) {
          _stopNavigation();
        } else {
          _startNavigation();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isNavigating
                ? [Colors.red.shade600, Colors.red.shade700]
                : [_orangeAccent, Colors.orange.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color:
                  (_isNavigating ? Colors.red : _orangeAccent).withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isNavigating ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              _isNavigating ? 'Stop Journey' : 'Start Journey',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
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
  // ignore: unused_element
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
    final totalDistance =
        _routePoints.isNotEmpty ? _routePoints.last.distanceFromUser : 0;
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
                  _buildRouteInfoStat(Icons.location_on,
                      '${_routePoints.length - _currentPointIndex}', 'Left'),
                ],
              ),
              const SizedBox(height: 12),
              // Navigation Start/Stop Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_isNavigating) {
                      _stopNavigation();
                    } else {
                      _startNavigation();
                    }
                  },
                  icon: Icon(
                    _isNavigating ? Icons.stop : Icons.navigation,
                    size: 20,
                  ),
                  label: Text(
                    _isNavigating ? 'Stop Navigation' : 'Start Navigation',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isNavigating
                        ? Colors.red.shade400
                        : Colors.green.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
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
