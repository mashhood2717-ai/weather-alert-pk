// lib/screens/home_screen.dart - WITH SKELETON LOADER & CLEAR SEARCH

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/weather_controller.dart';
import '../services/notification_service.dart';
import '../services/favorites_service.dart';
import '../services/places_service.dart';
import '../services/aqi_service.dart';
import '../services/settings_service.dart';
import '../services/persistent_notification_service.dart';
import '../services/prayer_service.dart';
import '../services/widget_service.dart';
import '../services/manual_alert_service.dart';
import '../services/user_service.dart';
import '../utils/background_utils.dart';
import '../utils/wind_utils.dart';
import '../utils/feels_like_utils.dart';
import '../widgets/current_weather_tile.dart';
import '../widgets/hourly_tile.dart';
import '../widgets/forecast_tile.dart';
import '../widgets/tiles_area.dart';
import '../widgets/sun_widget.dart';
import '../widgets/wu_widget.dart';
import '../widgets/aqi_bar_widget.dart';
import '../widgets/prayer_widget.dart';
import '../models/daily_weather.dart';
import '../models/current_weather.dart';
import 'settings_screen.dart';
import 'travel_weather_screen.dart';
import 'alerts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final WeatherController controller = WeatherController();
  final FavoritesService _favoritesService = FavoritesService();
  final SettingsService _settings = SettingsService();
  final PersistentNotificationService _persistentNotification =
      PersistentNotificationService();
  final WidgetService _widgetService = WidgetService();
  final TextEditingController _search = TextEditingController();

  bool loading = false;
  bool _isFavorite = false;
  List<FavoriteLocation> _favorites = [];

  // AQI data
  AirQualityData? _aqiData;
  bool _aqiLoading = false;

  // Prayer data for persistent notification
  DailyPrayerTimes? _prayerData;

  // Location auto-refresh
  Timer? _locationRefreshTimer;
  Position? _lastKnownPosition;
  static const double _locationChangeThreshold = 500; // meters

  // Developer debug mode (5 taps on weather icon)
  int _iconTapCount = 0;
  DateTime? _lastIconTap;

  // Place autocomplete
  List<PlaceSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  String? _sessionToken;
  Timer? _debounceTimer;

  late TabController tabs;
  WebViewController? windy;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _shimmerController;
  int _currentTabIndex = 0; // Track current tab for lazy loading

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 5, vsync: this);
    // Listen to tab changes for lazy loading
    tabs.addListener(_onTabChanged);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

    // Shimmer animation controller - DON'T repeat() here, control in loading state
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    controller.onDataLoaded = _onWeatherDataLoaded;
    controller.current.addListener(_onCurrentWeatherChanged);
    _initSettings();
    _loadInitial();
    _loadFavorites();
    _startLocationAutoRefresh();
    // Removed: tabs.addListener(() => setState(() {})) - causes unnecessary rebuilds
    _settings.addListener(_onSettingsChanged);

    // Initialize widget services in background (non-blocking)
    _initWidgetServices();
  }

  void _onTabChanged() {
    if (tabs.index != _currentTabIndex) {
      setState(() {
        _currentTabIndex = tabs.index;
      });
    }
  }

  Future<void> _initSettings() async {
    await _settings.initialize();
    if (mounted) setState(() {});
  }

  /// Initialize persistent notification and widget services (non-blocking)
  Future<void> _initWidgetServices() async {
    // Delay to not interfere with location permission
    await Future.delayed(const Duration(seconds: 2));

    // Ensure settings are initialized before proceeding
    if (!_settings.isInitialized) {
      await _settings.initialize();
    }

    await _persistentNotification.initialize();
    await _widgetService.initialize();
    _persistentNotification.setRefreshCallback(_onRefreshNotification);
    _widgetService.setRefreshCallback(_onRefreshNotification);
    // Sync persistent notification with traveling mode
    await _persistentNotification
        .syncWithTravelingMode(_settings.travelingMode);

    // Schedule prayer notifications for today (and tomorrow's Fajr)
    _schedulePrayerNotificationsOnStartup();
  }

  /// Schedule prayer notifications when app starts
  /// This ensures notifications are always scheduled, even if user doesn't open prayer widget
  Future<void> _schedulePrayerNotificationsOnStartup() async {
    try {
      // Get current location from controller or use default
      final coords = controller.getCurrentCoordinates();
      double lat = coords?.$1 ?? 33.6844; // Default Islamabad
      double lon = coords?.$2 ?? 73.0479;

      // Try to get device location if controller doesn't have it yet
      if (coords == null) {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 5),
          );
          lat = position.latitude;
          lon = position.longitude;
        } catch (_) {
          // Use default coordinates
        }
      }

      debugPrint('🕌 Scheduling prayer notifications for lat=$lat, lon=$lon');

      // Schedule notifications
      await PrayerService.scheduleNotifications(
        latitude: lat,
        longitude: lon,
      );
      debugPrint('✅ Prayer notifications scheduled on app startup');

      // Debug: Print pending notifications
      final pending = await NotificationService().getPendingNotifications();
      debugPrint('📋 Pending notifications: ${pending.length}');
      for (final n in pending.where((p) => p.id >= 1000 && p.id < 1040)) {
        debugPrint('   🔔 ID ${n.id}: ${n.title} - ${n.body}');
      }
    } catch (e) {
      debugPrint('❌ Error scheduling prayer notifications on startup: $e');
    }
  }

  /// Handle refresh button press from notification
  Future<void> _onRefreshNotification() async {
    if (controller.current.value != null) {
      final coords = controller.getCurrentCoordinates();
      if (coords != null) {
        // Preserve the current location flag during refresh
        final wasCurrentLocation = controller.isFromCurrentLocation;
        await controller.loadByCoordinates(
          coords.$1,
          coords.$2,
          isCurrentLocation: wasCurrentLocation,
        );
        await _fetchAqiData(coords.$1, coords.$2);
      }
    }
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
      // Restart location refresh if traveling mode changed
      _restartLocationRefresh();
      // Sync persistent notification with traveling mode
      _persistentNotification.syncWithTravelingMode(_settings.travelingMode);
    }
  }

  // Track last city to detect geocoding updates
  String? _lastNotifiedCity;

  /// Helper to set loading state and control shimmer animation
  void _setLoading(bool isLoading) {
    if (!mounted) return;
    setState(() => loading = isLoading);
    if (isLoading) {
      _shimmerController.repeat();
    } else {
      _shimmerController.stop();
      _shimmerController.reset();
    }
  }

  /// Called when current weather value changes (e.g. after geocoding updates city)
  void _onCurrentWeatherChanged() {
    final weather = controller.current.value;
    if (weather == null) return;

    // If city changed from Unknown to a real name, update notification
    final newCity = weather.city;
    if (_lastNotifiedCity == 'Unknown' &&
        newCity != 'Unknown' &&
        newCity.isNotEmpty) {
      final coords = controller.getCurrentCoordinates();
      if (coords != null && controller.isFromCurrentLocation) {
        _updatePersistentNotification(coords.$1, coords.$2);
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _shimmerController.dispose();
    tabs.removeListener(_onTabChanged);
    tabs.dispose();
    _search.dispose();
    _debounceTimer?.cancel();
    _locationRefreshTimer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    controller.current.removeListener(_onCurrentWeatherChanged);
    _persistentNotification.dispose();
    super.dispose();
  }

  /// Start auto-refreshing location for travelers
  void _startLocationAutoRefresh() {
    // Check location based on traveling mode
    // Battery optimization: reduced frequency (3 min traveling, 15 min normal)
    final interval = _settings.travelingMode
        ? const Duration(minutes: 3) // Traveling mode - balanced
        : const Duration(minutes: 15); // Normal mode - battery saving

    _locationRefreshTimer = Timer.periodic(
      interval,
      (_) => _checkLocationChange(),
    );
  }

  /// Restart location refresh when settings change
  void _restartLocationRefresh() {
    _locationRefreshTimer?.cancel();
    _startLocationAutoRefresh();
  }

  /// Check if location has changed significantly
  Future<void> _checkLocationChange() async {
    // Only check if traveling mode is enabled
    if (!_settings.travelingMode) return;

    try {
      // Battery optimization: medium accuracy is sufficient for weather updates
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.medium, // Balanced accuracy - saves battery
      );

      if (_lastKnownPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastKnownPosition!.latitude,
          _lastKnownPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        // If moved more than threshold, refresh weather
        if (distance > _locationChangeThreshold) {
          _lastKnownPosition = position;
          // Mark as current location since this is GPS-based auto-refresh
          await controller.loadByCoordinates(
            position.latitude,
            position.longitude,
            isCurrentLocation: true,
          );
          await _fetchAqiData(position.latitude, position.longitude);

          // Update Firestore location for accurate alert targeting while traveling
          ManualAlertService().refreshLocation();
        }
      } else {
        _lastKnownPosition = position;
        // Also update Firestore on first location acquisition
        ManualAlertService().refreshLocation();
      }
    } catch (e) {
      // Silently fail - location refresh is optional
      debugPrint('Location auto-refresh error: $e');
    }
  }

  /// Fetch AQI data for given coordinates
  Future<void> _fetchAqiData(double lat, double lon) async {
    setState(() {
      _aqiLoading = true;
    });

    try {
      final data = await AqiService.fetchAirQuality(lat, lon);
      if (mounted) {
        setState(() {
          _aqiData = data;
          _aqiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aqiLoading = false;
        });
      }
      debugPrint('AQI fetch error: $e');
    }
  }

  void _onSearchTextChanged(String value) {
    _debounceTimer?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    // Start a new session if needed
    _sessionToken ??= PlacesService.generateSessionToken();

    // Debounce to avoid too many API calls
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await PlacesService.getFullAutocompleteSuggestions(
        value,
        sessionToken: _sessionToken,
      );
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _showSuggestions = suggestions.isNotEmpty;
        });
      }
    });
  }

  Future<void> _onSuggestionSelected(PlaceSuggestion suggestion) async {
    // IMMEDIATELY hide dropdown and clear suggestions before any async work
    _showSuggestions = false;
    _suggestions = [];
    _search.clear();
    FocusScope.of(context).unfocus();

    _setLoading(true);
    _fadeController.reset();

    try {
      // Get place details to get coordinates
      final details = await PlacesService.getPlaceDetails(
        suggestion.placeId,
        sessionToken: _sessionToken,
      );

      // Reset session token after selection
      _sessionToken = null;

      if (details != null) {
        // Use coordinates to load weather with the place name
        await controller.loadByCoordinates(
          details.lat,
          details.lon,
          cityName: suggestion.mainText,
        );
        _fadeController.forward();
      } else {
        // Fallback to city search if details failed
        await controller.loadByCity(suggestion.mainText);
        _fadeController.forward();
      }
    } catch (e) {
      _showError('Search Error: ${e.toString()}');
    }

    _setLoading(false);
  }

  void _onWeatherDataLoaded() {
    if (!kIsWeb) _updateWindy();
    _checkIfFavorite();
    // Fetch AQI data for current location
    final coords = controller.getCurrentCoordinates();
    if (coords != null) {
      _fetchAqiData(coords.$1, coords.$2);
      _lastKnownPosition = null; // Reset position tracking for auto-refresh
      // Only update persistent notification and widget when using current GPS location
      // This ensures widget always shows current location, not searched location
      if (controller.isFromCurrentLocation) {
        _updatePersistentNotification(coords.$1, coords.$2);
      }
    }
    if (mounted) setState(() {});
  }

  /// Update persistent notification with current weather and next prayer
  Future<void> _updatePersistentNotification(double lat, double lon) async {
    final weather = controller.current.value;
    if (weather == null) return;

    try {
      // Calculate prayer times for current location
      _prayerData = await PrayerService.calculatePrayerTimes(
        latitude: lat,
        longitude: lon,
      );

      // Get temperature with unit
      final temp = _settings.convertTemperature(weather.tempC);
      final tempStr = '${temp.round()}${_settings.temperatureSymbol}';

      // Calculate feels like using wind chill / heat index
      // Rules: temp <= 15°C = wind chill, temp >= 25°C = heat index, else actual temp
      final calculatedFeelsLikeC = calculateFeelsLike(
        tempC: weather.tempC,
        humidity: weather.humidity.toDouble(),
        windKph: weather.windKph,
      );
      final feelsLike = _settings.convertTemperature(calculatedFeelsLikeC);
      final feelsLikeStr =
          'Feels like ${feelsLike.round()}${_settings.temperatureSymbol}';

      // Get wind with unit
      final windSpeed = _settings.convertWindSpeedHybrid(weather.windKph);
      final windStr = '${windSpeed.round()} ${_settings.windSymbolHybrid}';

      // Get next prayer info
      String nextPrayerName = '--';
      String nextPrayerTime = '--';
      if (_prayerData?.nextPrayer != null) {
        nextPrayerName = _prayerData!.nextPrayer!.name;
        nextPrayerTime = _prayerData!.nextPrayer!.formattedTime;
      }

      // Get all prayer times
      String fajr = '--:--',
          dhuhr = '--:--',
          asr = '--:--',
          maghrib = '--:--',
          isha = '--:--';
      if (_prayerData != null) {
        for (final prayer in _prayerData!.prayers) {
          final timeStr = _formatPrayerTime(prayer.time);
          switch (prayer.name) {
            case 'Fajr':
              fajr = timeStr;
              break;
            case 'Dhuhr':
              dhuhr = timeStr;
              break;
            case 'Asr':
              asr = timeStr;
              break;
            case 'Maghrib':
              maghrib = timeStr;
              break;
            case 'Isha':
              isha = timeStr;
              break;
          }
        }
      }

      // Update notification (track city for geocoding updates)
      _lastNotifiedCity = weather.city;
      await _persistentNotification.updateNotification(
        condition: weather.condition,
        temperature: tempStr,
        nextPrayer: nextPrayerName,
        nextPrayerTime: nextPrayerTime,
        city: weather.city,
      );

      // Update home screen widget
      await _widgetService.updateWidget(
        city: weather.city,
        temp: tempStr,
        condition: weather.condition,
        feelsLike: feelsLikeStr,
        humidity: '${weather.humidity}%',
        wind: windStr,
        uv: (weather.uvIndex ?? 0).toStringAsFixed(1),
        isDay: weather.isDay == 1,
        nextPrayer: nextPrayerName,
        nextPrayerTime: nextPrayerTime,
        fajr: fajr,
        dhuhr: dhuhr,
        asr: asr,
        maghrib: maghrib,
        isha: isha,
      );
    } catch (e) {
      debugPrint('Error updating persistent notification: $e');
    }
  }

  /// Format prayer time for widget display
  String _formatPrayerTime(DateTime time) {
    final hour =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _loadFavorites() async {
    final favorites = await _favoritesService.getFavorites();
    if (mounted) setState(() => _favorites = favorites);
  }

  Future<void> _checkIfFavorite() async {
    final cityName =
        controller.current.value?.city ?? controller.lastCitySearched;
    if (cityName != null) {
      final isFav = await _favoritesService.isFavorite(cityName);
      if (mounted) setState(() => _isFavorite = isFav);
    }
  }

  Future<void> _toggleFavorite() async {
    final c = controller.current.value;
    if (c == null) return;
    final location = FavoriteLocation(
      name: c.city,
      lat: c.lat,
      lon: c.lon,
      icao: controller.metar?['station'],
    );
    final isNowFavorite = await _favoritesService.toggleFavorite(location);
    if (mounted) {
      setState(() => _isFavorite = isNowFavorite);
      await _loadFavorites();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isNowFavorite
            ? '${c.city} added to favorites'
            : '${c.city} removed from favorites'),
        backgroundColor: isNowFavorite ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _loadFavoriteLocation(FavoriteLocation fav) async {
    _setLoading(true);
    _fadeController.reset();
    Navigator.pop(context);
    try {
      await controller.loadByCoordinates(fav.lat, fav.lon, cityName: fav.name);
      _fadeController.forward();
    } catch (e) {
      _showError('Error loading ${fav.name}');
    }
    _setLoading(false);
  }

  void _showFavoritesSheet(bool isDay) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildFavoritesSheet(isDay),
    );
  }

  Widget _buildFavoritesSheet(bool isDay) {
    final fg = isDay ? Colors.black87 : Colors.white;
    final bgColor = isDay
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.grey[900]!.withValues(alpha: 0.95);
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2))),
          Row(children: [
            Icon(Icons.star_rounded, color: Colors.amber, size: 24),
            const SizedBox(width: 10),
            Text('Favorite Locations',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: fg)),
            const Spacer(),
            Text('${_favorites.length}/10',
                style:
                    TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.6))),
          ]),
          const SizedBox(height: 16),
          Flexible(
            child: _favorites.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_border_rounded,
                        size: 48, color: fg.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('No favorites yet',
                        style: TextStyle(
                            color: fg.withValues(alpha: 0.6), fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('Tap the star icon to add locations',
                        style: TextStyle(
                            color: fg.withValues(alpha: 0.4), fontSize: 13)),
                  ]))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _favorites.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _buildFavoriteItem(_favorites[index], fg, isDay),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteItem(FavoriteLocation fav, Color fg, bool isDay) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _loadFavoriteLocation(fav),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: fg.withValues(alpha: 0.1))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.location_on_rounded,
                    color: Colors.blue, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(fav.name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: fg)),
                  if (fav.icao != null)
                    Text(fav.icao!,
                        style: TextStyle(
                            fontSize: 12, color: fg.withValues(alpha: 0.5))),
                ])),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: Colors.red.withValues(alpha: 0.7), size: 20),
              onPressed: () async {
                await _favoritesService.removeFavorite(fav.name);
                await _loadFavorites();
                await _checkIfFavorite();
                if (mounted) Navigator.pop(context);
                _showFavoritesSheet(isDay);
              },
            ),
          ]),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(message))
        ]),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  Future<void> _showFcmTokenDialog() async {
    final token = await NotificationService().getToken();
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('FCM Debug Info'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FCM Token:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8)),
                        child: SelectableText(token ?? 'No token available',
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'))),
                  ]),
              actions: [
                TextButton(
                    onPressed: () {
                      if (token != null) {
                        Clipboard.setData(ClipboardData(text: token));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Token copied to clipboard')));
                      }
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Copy & Close'))
              ],
            ));
  }

  /// Developer debug dialog - shown after 5 taps on weather icon
  Future<void> _showDeveloperDebugDialog() async {
    final token = await NotificationService().getToken();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id') ?? 'Not set';
    final userService = UserService();
    final userId = userService.userId;
    final userName = userService.userName;
    final c = controller.current.value;
    final coords = controller.getCurrentCoordinates();

    if (!mounted) return;
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Row(children: [
                const Icon(Icons.developer_mode, color: Colors.deepPurple),
                const SizedBox(width: 8),
                const Text('Developer Debug'),
              ]),
              content: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _debugSectionWithCopy(
                        'User Info',
                        [
                          'Name: $userName',
                          'User ID: $userId',
                        ],
                        ctx),
                    _debugSectionWithCopy(
                        'Device Info',
                        [
                          'Device ID: $deviceId',
                          'Is GPS Location: ${controller.isFromCurrentLocation}',
                        ],
                        ctx),
                    _debugSectionWithCopy(
                        'FCM Token',
                        [
                          token ?? 'No token',
                        ],
                        ctx,
                        isMonospace: true),
                    _debugSectionWithCopy(
                        'Location Data',
                        [
                          'City: ${c?.city ?? "--"}',
                          'Lat: ${coords?.$1 ?? "--"}',
                          'Lon: ${coords?.$2 ?? "--"}',
                          'Street: ${c?.streetAddress ?? "--"}',
                        ],
                        ctx),
                    _debugSectionWithCopy(
                        'Weather Source',
                        [
                          'METAR Applied: ${controller.metarApplied}',
                          'Last City Searched: ${controller.lastCitySearched ?? "--"}',
                        ],
                        ctx),
                    const Divider(),
                    const Text('📍 Motorway Testing Tips:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 4),
                    const Text(
                      '1. Enable Traveling Mode in Settings\n'
                      '2. Location refreshes every 1 min in traveling mode\n'
                      '3. Check if street address updates while moving\n'
                      '4. GPS location should show area name, not "Unknown"\n'
                      '5. Widget only updates for GPS location, not searched cities',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ])),
              actions: [
                TextButton(
                    onPressed: () {
                      final debugText = '''
User: $userName
User ID: $userId
Device ID: $deviceId
FCM Token: $token
City: ${c?.city}
Coords: ${coords?.$1}, ${coords?.$2}
Street: ${c?.streetAddress}
METAR: ${controller.metarApplied}
Is GPS: ${controller.isFromCurrentLocation}
''';
                      Clipboard.setData(ClipboardData(text: debugText));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Debug info copied!')));
                    },
                    child: const Text('Copy All')),
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close')),
              ],
            ));
  }

  Widget _debugSectionWithCopy(
      String title, List<String> lines, BuildContext ctx,
      {bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: lines.join('\n')));
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('$title copied!'),
                      duration: const Duration(seconds: 1)));
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 12, color: Colors.deepPurple),
                      SizedBox(width: 4),
                      Text('Copy',
                          style: TextStyle(
                              fontSize: 10, color: Colors.deepPurple)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines
                  .map((l) => SelectableText(
                        l,
                        style: TextStyle(
                          fontSize: isMonospace ? 9 : 11,
                          fontFamily: isMonospace ? 'monospace' : null,
                          color: Colors.black87,
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Handle tap on weather icon - 5 taps to show debug
  void _onWeatherIconTap() {
    final now = DateTime.now();
    if (_lastIconTap != null && now.difference(_lastIconTap!).inSeconds > 2) {
      _iconTapCount = 0; // Reset if more than 2 seconds between taps
    }
    _lastIconTap = now;
    _iconTapCount++;

    if (_iconTapCount >= 5) {
      _iconTapCount = 0;
      _showDeveloperDebugDialog();
    } else if (_iconTapCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${5 - _iconTapCount} more taps for debug mode'),
          duration: const Duration(milliseconds: 500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadInitial() async {
    _setLoading(true);
    try {
      // Request location permission immediately on fresh install
      // FCM permission is delayed in main.dart to avoid conflict
      await controller.loadByLocation();
      _fadeController.forward();
    } catch (e) {
      _showError('Location Error: ${e.toString().split(':').last.trim()}');
    }
    _setLoading(false);
  }

  Future<void> _onSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    _setLoading(true);
    _showSuggestions = false;
    _suggestions = [];
    _fadeController.reset();
    _search.clear(); // Clear search text after searching
    FocusScope.of(context).unfocus(); // Hide keyboard
    try {
      await controller.loadByCity(q);
      _fadeController.forward();
      if (controller.metarApplied && controller.rawWeatherJson == null) {
        tabs.animateTo(3);
      }
    } catch (e) {
      _showError('Search Error: ${e.toString()}');
    }
    _setLoading(false);
  }

  void _updateWindy() {
    if (kIsWeb) return; // WebView not supported on web
    double lat = 30.0, lon = 70.0;
    final coords = controller.getCurrentCoordinates();
    if (coords != null) {
      lat = coords.$1;
      lon = coords.$2;
    }
    final url =
        'https://embed.windy.com/embed2.html?lat=$lat&lon=$lon&zoom=8&overlay=wind&level=surface&marker=true';
    if (windy == null) {
      windy = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(url));
    } else {
      windy!.loadRequest(Uri.parse(url));
    }
  }

  // ==================== SKELETON LOADER WIDGETS ====================

  Widget _buildSkeletonLoader(bool isDay) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildSkeletonWeatherCard(isDay),
        const SizedBox(height: 12),
        _buildSkeletonSection(isDay, "Hourly Forecast"),
        const SizedBox(height: 8),
        _buildSkeletonHourlyList(isDay),
        const SizedBox(height: 14),
        _buildSkeletonTiles(isDay),
        const SizedBox(height: 12),
        _buildSkeletonSunWidget(isDay),
        const SizedBox(height: 14),
        _buildSkeletonSection(isDay, "7-Day Forecast"),
        const SizedBox(height: 8),
        ...List.generate(5, (_) => _buildSkeletonForecastTile(isDay)),
      ],
    );
  }

  Widget _buildShimmerEffect({required Widget child, required bool isDay}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: isDay
                  ? [
                      Colors.grey.shade300,
                      Colors.grey.shade100,
                      Colors.grey.shade300
                    ]
                  : [
                      Colors.grey.shade800,
                      Colors.grey.shade600,
                      Colors.grey.shade800
                    ],
              stops: [
                _shimmerController.value - 0.3,
                _shimmerController.value,
                _shimmerController.value + 0.3,
              ].map((s) => s.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }

  Widget _buildSkeletonBox({
    required double width,
    required double height,
    required bool isDay,
    double borderRadius = 8,
  }) {
    return _buildShimmerEffect(
      isDay: isDay,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDay ? Colors.grey.shade300 : Colors.grey.shade700,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }

  Widget _buildSkeletonWeatherCard(bool isDay) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDay
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSkeletonBox(width: 120, height: 14, isDay: isDay),
                    const SizedBox(height: 8),
                    _buildSkeletonBox(
                        width: 80, height: 52, isDay: isDay, borderRadius: 12),
                    const SizedBox(height: 8),
                    _buildSkeletonBox(width: 100, height: 14, isDay: isDay),
                  ],
                ),
              ),
              _buildSkeletonBox(
                  width: 60, height: 60, isDay: isDay, borderRadius: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonSection(bool isDay, String title) {
    return _buildSkeletonBox(width: 120, height: 15, isDay: isDay);
  }

  Widget _buildSkeletonHourlyList(bool isDay) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, __) => _buildSkeletonHourlyTile(isDay),
      ),
    );
  }

  Widget _buildSkeletonHourlyTile(bool isDay) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          width: 70,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: isDay
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSkeletonBox(width: 30, height: 11, isDay: isDay),
              const SizedBox(height: 8),
              _buildSkeletonBox(
                  width: 32, height: 32, isDay: isDay, borderRadius: 16),
              const SizedBox(height: 8),
              _buildSkeletonBox(width: 28, height: 14, isDay: isDay),
              const SizedBox(height: 6),
              _buildSkeletonBox(width: 24, height: 10, isDay: isDay),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonTiles(bool isDay) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _buildSkeletonParamTile(isDay)),
          const SizedBox(width: 8),
          Expanded(child: _buildSkeletonParamTile(isDay)),
          const SizedBox(width: 8),
          Expanded(child: _buildSkeletonParamTile(isDay)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildSkeletonParamTile(isDay)),
          const SizedBox(width: 8),
          Expanded(child: _buildSkeletonParamTile(isDay)),
          const SizedBox(width: 8),
          Expanded(child: _buildSkeletonParamTile(isDay)),
        ]),
      ],
    );
  }

  Widget _buildSkeletonParamTile(bool isDay) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isDay
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSkeletonBox(width: 40, height: 10, isDay: isDay),
              const SizedBox(height: 6),
              _buildSkeletonBox(width: 35, height: 14, isDay: isDay),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonSunWidget(bool isDay) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDay
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              _buildSkeletonBox(
                  width: double.infinity,
                  height: 70,
                  isDay: isDay,
                  borderRadius: 12),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Row(children: [
                    _buildSkeletonBox(
                        width: 20, height: 20, isDay: isDay, borderRadius: 10),
                    const SizedBox(width: 8),
                    _buildSkeletonBox(width: 50, height: 14, isDay: isDay),
                  ]),
                  Row(children: [
                    _buildSkeletonBox(
                        width: 20, height: 20, isDay: isDay, borderRadius: 10),
                    const SizedBox(width: 8),
                    _buildSkeletonBox(width: 50, height: 14, isDay: isDay),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonForecastTile(bool isDay) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDay
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                _buildSkeletonBox(
                    width: 36, height: 36, isDay: isDay, borderRadius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSkeletonBox(width: 60, height: 13, isDay: isDay),
                      const SizedBox(height: 4),
                      _buildSkeletonBox(width: 80, height: 11, isDay: isDay),
                    ],
                  ),
                ),
                _buildSkeletonBox(width: 50, height: 16, isDay: isDay),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== END SKELETON LOADER ====================

  /// Determine if day mode should be used based on settings and weather data
  bool _getIsDay(CurrentWeather? c) {
    switch (_settings.themeMode) {
      case AppThemeMode.light:
        return true;
      case AppThemeMode.dark:
        return false;
      case AppThemeMode.system:
        // Use system brightness
        final brightness = MediaQuery.of(context).platformBrightness;
        return brightness == Brightness.light;
      case AppThemeMode.auto:
        // Use sunrise/sunset (original behavior)
        return (c?.isDay ?? 1) == 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CurrentWeather?>(
      valueListenable: controller.current,
      builder: (context, c, _) {
        final isDay = _getIsDay(c);
        final condition = c?.condition ?? "";
        final hasData = c != null || controller.metar != null;
        final dailyData =
            controller.daily.isNotEmpty ? controller.daily.first : null;
        final windDirection = windDegToCompass(c?.windDeg);

        // Update status bar icons based on day/night mode
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDay ? Brightness.dark : Brightness.light,
          statusBarBrightness: isDay ? Brightness.light : Brightness.dark,
        ));

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Container(
            decoration:
                BoxDecoration(gradient: dynamicGradient(condition, isDay)),
            child: SafeArea(
                child: Column(children: [
              _buildModernAppBar(isDay),
              _buildModernSearchBar(isDay),
              Expanded(
                child: loading
                    ? _buildSkeletonLoader(isDay)
                    : !hasData
                        ? _buildEmptyState(isDay)
                        : FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(children: [
                              Expanded(
                                  child:
                                      TabBarView(controller: tabs, children: [
                                _buildHomeTab(
                                    c, windDirection, dailyData, isDay),
                                _buildWindyTab(),
                                _buildAlertsTab(isDay),
                                WuWidget(
                                  isDay: isDay,
                                  isActive: _currentTabIndex == 3,
                                  city: c?.city ?? controller.lastCitySearched,
                                  userLat: c?.lat,
                                  userLon: c?.lon,
                                  onDataLoaded: (data) {},
                                ),
                                _buildPrayerTab(c, isDay),
                              ])),
                              _buildModernTabBar(isDay),
                            ])),
              ),
            ])),
          ),
        );
      },
    );
  }

  Widget _buildModernAppBar(bool isDay) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
                color: isDay
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15), width: 1)),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset('assets/images/logo.png',
                    width: 32, height: 32, fit: BoxFit.contain))),
        // Expanded spacer for layout (logo on left, icons on right)
        const SizedBox(width: 8),
        Expanded(
            child: GestureDetector(
                onLongPress: _showFcmTokenDialog, child: const SizedBox())),
        // App bar buttons - compact layout to fit 6 buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAppBarButton(
                icon: Icons.star_rounded,
                isDay: isDay,
                iconColor: _favorites.isNotEmpty ? Colors.amber : null,
                onTap: () => _showFavoritesSheet(isDay)),
            const SizedBox(width: 4),
            _buildAppBarButton(
                icon: Icons.my_location_rounded,
                isDay: isDay,
                onTap: () async {
                  _setLoading(true);
                  _fadeController.reset();
                  try {
                    await controller.loadByLocation();
                    _fadeController.forward();
                  } catch (e) {
                    _showError(
                        'Location Error: ${e.toString().split(':').last.trim()}');
                  }
                  _setLoading(false);
                }),
            const SizedBox(width: 4),
            _buildAppBarButton(
                icon: Icons.directions_car_rounded,
                isDay: isDay,
                iconColor: isDay ? Colors.blue.shade700 : Colors.blue.shade300,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            TravelWeatherScreen(isDay: isDay)))),
            const SizedBox(width: 4),
            _buildAppBarButton(
                icon: Icons.settings_rounded,
                isDay: isDay,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => SettingsScreen(isDay: isDay)))),
            const SizedBox(width: 4),
            _buildAppBarButton(
                icon: Icons.admin_panel_settings,
                isDay: isDay,
                iconColor: isDay ? Colors.deepPurple : Colors.purple.shade300,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Long press to access Admin Portal'),
                        duration: Duration(seconds: 1))),
                onLongPress: () => Navigator.pushNamed(context, '/admin')),
          ],
        ),
      ]),
    );
  }

  Widget _buildAppBarButton(
      {required IconData icon,
      required bool isDay,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
      Color? iconColor}) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(10),
            child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: isDay
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15), width: 1)),
                child: Icon(icon,
                    color: iconColor ??
                        (isDay
                            ? Colors.black.withValues(alpha: 0.87)
                            : Colors.white),
                    size: 18))));
  }

  Widget _buildModernSearchBar(bool isDay) {
    final fg = isDay ? Colors.black : Colors.white;
    final bgColor = isDay
        ? Colors.white.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.25);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search bar
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.87),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: "Search any location / ICAO...",
                          hintStyle: TextStyle(
                            color: fg.withValues(alpha: 0.45),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: fg.withValues(alpha: 0.54),
                            size: 20,
                          ),
                          suffixIcon: _search.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: fg.withValues(alpha: 0.54),
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {
                                      _suggestions = [];
                                      _showSuggestions = false;
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onChanged: _onSearchTextChanged,
                        onSubmitted: (_) => _onSearch(),
                      ),
                    ),
                    if (controller.current.value != null)
                      IconButton(
                        icon: Icon(
                          _isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: _isFavorite
                              ? Colors.amber
                              : fg.withValues(alpha: 0.54),
                          size: 22,
                        ),
                        onPressed: _toggleFavorite,
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        color: fg.withValues(alpha: 0.54),
                        size: 20,
                      ),
                      onPressed: _onSearch,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Suggestions dropdown
          if (_showSuggestions && _suggestions.isNotEmpty)
            _buildSuggestionsDropdown(isDay),
        ],
      ),
    );
  }

  Widget _buildSuggestionsDropdown(bool isDay) {
    final fg = isDay ? Colors.black : Colors.white;
    final bgColor = isDay
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.grey[900]!.withValues(alpha: 0.95);

    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          itemBuilder: (context, index) {
            final suggestion = _suggestions[index];
            return InkWell(
              onTap: () => _onSuggestionSelected(suggestion),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: index < _suggestions.length - 1
                      ? Border(
                          bottom: BorderSide(
                            color: fg.withValues(alpha: 0.1),
                            width: 0.5,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: fg.withValues(alpha: 0.5),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion.mainText,
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.87),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (suggestion.secondaryText.isNotEmpty)
                            Text(
                              suggestion.secondaryText,
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.north_west_rounded,
                      color: fg.withValues(alpha: 0.3),
                      size: 16,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWeatherCard(dynamic c, String windDirection, bool isDay) {
    // Convert temperature and wind based on settings
    final tempValue =
        c?.tempC != null ? _settings.convertTemperature(c!.tempC) : null;
    final windValue = c?.windKph != null
        ? _settings.convertWindSpeedHybrid(c!.windKph!)
        : null;
    final dewValue = c?.dewpointC != null
        ? _settings.convertTemperature(c!.dewpointC!)
        : null;

    return GestureDetector(
      onTap: _onWeatherIconTap, // 5 taps anywhere on card to show debug panel
      child: Stack(children: [
        CurrentWeatherTile(
            city: c?.city ?? controller.lastCitySearched ?? "--",
            temp:
                "${tempValue?.toStringAsFixed(1) ?? '--'}${_settings.temperatureSymbol}",
            condition: c?.condition ?? "Data Unavailable",
            icon: c?.icon ?? '',
            humidity: "${c?.humidity ?? '--'}%",
            wind:
                "${windValue?.toStringAsFixed(0) ?? '--'} ${_settings.windSymbolHybrid}",
            dew:
                "${dewValue?.toStringAsFixed(1) ?? '--'}${_settings.temperatureSymbol}",
            pressure: "${c?.pressureMb?.toStringAsFixed(0) ?? '--'} mb",
            windDir: windDirection,
            isDay: isDay,
            streetAddress: c?.streetAddress),
        if (controller.metarApplied)
          Positioned(
              top: 10,
              right: 10,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.red.shade400.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.flight,
                                size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                                'METAR ${_formatMetarTime(controller.metar?["observed"])}',
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3))
                          ]))))),
      ]),
    );
  }

  Widget _buildEmptyState(bool isDay) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: isDay
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.2),
              shape: BoxShape.circle),
          child: Icon(Icons.cloud_off_rounded,
              size: 60,
              color: isDay
                  ? Colors.black.withValues(alpha: 0.26)
                  : Colors.white.withValues(alpha: 0.3))),
      const SizedBox(height: 20),
      Text("No Weather Data",
          style: TextStyle(
              fontSize: 20,
              color:
                  isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text("Search a city or use your location",
          style: TextStyle(
              fontSize: 14,
              color: isDay
                  ? Colors.black.withValues(alpha: 0.54)
                  : Colors.white.withValues(alpha: 0.6))),
    ]));
  }

  Widget _buildModernTabBar(bool isDay) {
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: isDay
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15), width: 1)),
        child: TabBar(
            controller: tabs,
            labelColor:
                isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
            unselectedLabelColor: isDay
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.5),
            labelStyle: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.2),
            unselectedLabelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDay
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.4),
                boxShadow: [
                  BoxShadow(
                      color: isDay
                          ? Colors.black.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ]),
            indicatorPadding:
                const EdgeInsets.symmetric(horizontal: -2, vertical: 2),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(icon: Icon(Icons.home_rounded, size: 22)),
              Tab(icon: Icon(Icons.waves_rounded, size: 22)),
              Tab(icon: Icon(Icons.notifications_rounded, size: 22)),
              Tab(icon: Icon(Icons.sensors_rounded, size: 22)),
              Tab(icon: Icon(Icons.mosque_rounded, size: 22)),
            ]));
  }

  Widget _buildHomeTab(
      dynamic c, String windDirection, DailyWeather? dailyData, bool isDay) {
    return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        cacheExtent: 500, // Cache more items to reduce rebuilds
        children: [
          // Main Weather Card
          RepaintBoundary(child: _buildWeatherCard(c, windDirection, isDay)),
          const SizedBox(height: 12),
          // AQI Bar (tappable to open AQI details)
          RepaintBoundary(
            child: AqiBarWidget(
              aqiData: _aqiData,
              isDay: isDay,
              isLoading: _aqiLoading,
            ),
          ),
          const SizedBox(height: 12),
          // Current Weather Tiles
          RepaintBoundary(child: TilesArea(controller: controller)),
          const SizedBox(height: 14),
          // Hourly Forecast
          if (controller.hourly.isNotEmpty) ...[
            _buildSectionTitle("Hourly Forecast", isDay),
            const SizedBox(height: 8),
            RepaintBoundary(
              child: SizedBox(
                  height: 130,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      cacheExtent: 300, // Pre-build more hourly tiles
                      itemCount: controller.hourly.length > 24
                          ? 24
                          : controller.hourly.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final h = controller.hourly[i];
                        final hourlyTemp =
                            _settings.convertTemperature(h.tempC);
                        return HourlyTile(
                            time: h.time,
                            temp: "${hourlyTemp.toStringAsFixed(0)}°",
                            icon: h.icon,
                            humidity: h.humidity.toString(),
                            isDay: isDay);
                      })),
            ),
            const SizedBox(height: 14),
          ],
          // Sunrise/Sunset
          if (dailyData != null)
            RepaintBoundary(
              child: SunWidget(
                  sunrise: dailyData.sunrise,
                  sunset: dailyData.sunset,
                  isDay: isDay),
            ),
          const SizedBox(height: 14),
          // 7-Day Forecast
          if (controller.daily.isNotEmpty) ...[
            _buildSectionTitle("7-Day Forecast", isDay),
            const SizedBox(height: 8),
            ...controller.daily.map((d) {
              final maxTemp = _settings.convertTemperature(d.maxTemp);
              final minTemp = _settings.convertTemperature(d.minTemp);
              return RepaintBoundary(
                child: ForecastTile(
                    date: d.date,
                    icon: d.icon,
                    condition: d.condition,
                    maxTemp: maxTemp.toStringAsFixed(0),
                    minTemp: minTemp.toStringAsFixed(0),
                    isDay: isDay,
                    dailyWeather: d,
                    feelsLikeHigh: maxTemp + (d.uvIndexMax ?? 0) * 0.5,
                    feelsLikeLow: minTemp - 2),
              );
            }),
          ],
          const SizedBox(height: 8),
        ]);
  }

  Widget _buildSectionTitle(String title, bool isDay) {
    return Text(title,
        style: TextStyle(
            color: isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2));
  }

  /// Alerts tab - embedded alerts screen
  Widget _buildAlertsTab(bool isDay) {
    return const AlertsScreen(embedded: true);
  }

  Widget _buildWindyTab() {
    if (kIsWeb) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Windy map is not available on web.\nPlease use the mobile app.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }
    if (windy == null) _updateWindy();
    if (windy == null) return const Center(child: CircularProgressIndicator());
    return WebViewWidget(controller: windy!);
  }

  Widget _buildPrayerTab(CurrentWeather? c, bool isDay) {
    return PrayerWidget(
      latitude: c?.lat ?? 33.6844,
      longitude: c?.lon ?? 73.0479,
      isDay: isDay,
      cityName: c?.city,
    );
  }

  /// Format METAR observation time from ISO string to PST (UTC+5)
  String _formatMetarTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      // Convert UTC to PST (Pakistan Standard Time = UTC+5)
      final pst = dt.add(const Duration(hours: 5));
      final hours = pst.hour.toString().padLeft(2, '0');
      final minutes = pst.minute.toString().padLeft(2, '0');
      return '@ $hours:$minutes';
    } catch (_) {
      return '';
    }
  }
}
