// lib/screens/home_screen.dart - PROFESSIONAL UI - FINAL CLEAN

import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/weather_controller.dart';
import '../services/notification_service.dart';
import '../utils/background_utils.dart';
import '../utils/wind_utils.dart';
import '../widgets/current_weather_tile.dart';
import '../widgets/hourly_tile.dart';
import '../widgets/forecast_tile.dart';
import '../widgets/metar_tile.dart';
import '../widgets/tiles_area.dart';
import '../widgets/sun_widget.dart';
import '../widgets/wu_widget.dart';
import '../models/daily_weather.dart';
import '../models/current_weather.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final WeatherController controller = WeatherController();
  final TextEditingController _search = TextEditingController();
  bool loading = false;
  late TabController tabs;
  WebViewController? windy;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 6, vsync: this);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _loadInitial();
    tabs.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  /// Show FCM token dialog (for debugging push notifications)
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
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                token ?? 'No token available',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (token != null) {
                Clipboard.setData(ClipboardData(text: token));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Token copied to clipboard')),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Copy & Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadInitial() async {
    setState(() => loading = true);
    try {
      await controller.loadByLocation();
      _updateWindy();
      _fadeController.forward();
    } catch (e) {
      _showError('Location Error: ${e.toString().split(':').last.trim()}');
    }
    setState(() => loading = false);
  }

  Future<void> _onSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;

    setState(() => loading = true);
    _fadeController.reset();

    try {
      await controller.loadByCity(q);
      _updateWindy();
      _fadeController.forward();

      if (controller.metarApplied && controller.rawWeatherJson == null) {
        tabs.animateTo(4);
      }
    } catch (e) {
      _showError('Search Error: ${e.toString()}');
    }

    setState(() => loading = false);
  }

  void _updateWindy() {
    double lat = 30.0;
    double lon = 70.0;

    final current = controller.current.value;
    if (current != null && current.lat != 0.0 && current.lon != 0.0) {
      lat = current.lat;
      lon = current.lon;
    } else if (controller.rawWeatherJson != null) {
      // Open-Meteo API returns lat/lon at root level
      lat = (controller.rawWeatherJson?['latitude'] ?? 30.0).toDouble();
      lon = (controller.rawWeatherJson?['longitude'] ?? 70.0).toDouble();
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CurrentWeather?>(
      valueListenable: controller.current,
      builder: (context, c, _) {
        final isDay = (c?.isDay ?? 1) == 1;
        final String condition = c?.condition ?? "";
        final bool hasData = c != null || controller.metar != null;
        final DailyWeather? dailyData =
            controller.daily.isNotEmpty ? controller.daily.first : null;
        final windDirection = windDegToCompass(c?.windDeg);

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Container(
            decoration: BoxDecoration(
              gradient: dynamicGradient(condition, isDay),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildModernAppBar(isDay),
                  _buildModernSearchBar(isDay),
                  Expanded(
                    child: loading
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading weather data...',
                                  style: TextStyle(
                                    color: isDay
                                        ? Colors.black.withValues(alpha: 0.54)
                                        : Colors.white.withValues(alpha: 0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : !hasData
                            ? _buildEmptyState(isDay)
                            : FadeTransition(
                                opacity: _fadeAnimation,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: TabBarView(
                                        controller: tabs,
                                        children: [
                                          _buildHomeTab(c, windDirection,
                                              dailyData, isDay),
                                          _buildHourlyTab(isDay),
                                          _buildRawTab(isDay),
                                          _buildWindyTab(),
                                          _buildMetarTab(isDay),
                                          WuWidget(
                                            isDay: isDay,
                                            onDataLoaded: (data) {},
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildModernTabBar(isDay),
                                  ],
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernAppBar(bool isDay) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDay
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.wb_sunny_rounded,
              color: isDay ? Colors.orange.shade700 : Colors.orange.shade300,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onLongPress: _showFcmTokenDialog,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Weather Alert",
                    style: TextStyle(
                      color: isDay ? Colors.black : Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    "Pakistan",
                    style: TextStyle(
                      color: isDay
                          ? Colors.black.withValues(alpha: 0.54)
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                setState(() => loading = true);
                _fadeController.reset();
                try {
                  await controller.loadByLocation();
                  _updateWindy();
                  _fadeController.forward();
                } catch (e) {
                  _showError(
                      'Location Error: ${e.toString().split(':').last.trim()}');
                }
                setState(() => loading = false);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDay
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.my_location_rounded,
                  color: isDay
                      ? Colors.black.withValues(alpha: 0.87)
                      : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, '/alerts'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDay
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.notifications_rounded,
                  color: isDay
                      ? Colors.black.withValues(alpha: 0.87)
                      : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Admin Portal (long press to access)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onLongPress: () => Navigator.pushNamed(context, '/admin'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Long press to access Admin Portal'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDay
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.admin_panel_settings,
                  color: isDay
                      ? Colors.deepPurple.withValues(alpha: 0.87)
                      : Colors.purple.shade300,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSearchBar(bool isDay) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDay
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: _search,
              style: TextStyle(
                color:
                    isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: "Search city or ICAO code...",
                hintStyle: TextStyle(
                  color: isDay
                      ? Colors.black.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isDay
                      ? Colors.black.withValues(alpha: 0.54)
                      : Colors.white.withValues(alpha: 0.7),
                  size: 22,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.send_rounded,
                    color: isDay
                        ? Colors.black.withValues(alpha: 0.54)
                        : Colors.white.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  onPressed: _onSearch,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onSubmitted: (_) => _onSearch(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard(dynamic c, String windDirection, bool isDay) {
    return Stack(
      children: [
        CurrentWeatherTile(
          city: c?.city ?? controller.lastCitySearched ?? "--",
          temp: "${c?.tempC.toStringAsFixed(1) ?? '--'}°C",
          condition: c?.condition ?? "Data Unavailable",
          icon: c?.icon ?? '',
          humidity: "${c?.humidity ?? '--'}%",
          wind: "${c?.windKph?.toStringAsFixed(0) ?? '--'} km/h",
          dew: "${c?.dewpointC?.toStringAsFixed(1) ?? '--'}°C",
          pressure: "${c?.pressureMb?.toStringAsFixed(0) ?? '--'} mb",
          windDir: windDirection,
          isDay: isDay,
        ),
        if (controller.metarApplied)
          Positioned(
            top: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flight, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'METAR',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDay) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDay
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_rounded,
              size: 80,
              color: isDay
                  ? Colors.black.withValues(alpha: 0.26)
                  : Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "No Weather Data",
            style: TextStyle(
              fontSize: 24,
              color:
                  isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Search a city or use your location",
            style: TextStyle(
              fontSize: 15,
              color: isDay
                  ? Colors.black.withValues(alpha: 0.54)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTabBar(bool isDay) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDay
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: TabBar(
        controller: tabs,
        labelColor: isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
        unselectedLabelColor: isDay
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.5),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDay
              ? Colors.white.withValues(alpha: 0.5)
              : Colors.black.withValues(alpha: 0.4),
          boxShadow: [
            BoxShadow(
              color: isDay
                  ? Colors.black.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorPadding:
            const EdgeInsets.symmetric(horizontal: -2, vertical: 2),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: "Home"),
          Tab(text: "Hourly"),
          Tab(text: "Raw"),
          Tab(text: "Windy"),
          Tab(text: "METAR"),
          Tab(text: "WU"),
        ],
      ),
    );
  }

  Widget _buildHomeTab(
      dynamic c, String windDirection, DailyWeather? dailyData, bool isDay) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Main Weather Card - now scrollable
        _buildWeatherCard(c, windDirection, isDay),
        const SizedBox(height: 16),
        TilesArea(controller: controller),
        const SizedBox(height: 16),
        if (dailyData != null)
          SunWidget(
            sunrise: dailyData.sunrise,
            sunset: dailyData.sunset,
            isDay: isDay,
          ),
        const SizedBox(height: 20),
        if (controller.daily.isNotEmpty) ...[
          Text(
            "7-Day Forecast",
            style: TextStyle(
              color:
                  isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          ...controller.daily.map((d) => ForecastTile(
                date: d.date,
                icon: d.icon,
                condition: d.condition,
                maxTemp: d.maxTemp.toStringAsFixed(1),
                minTemp: d.minTemp.toStringAsFixed(1),
                isDay: isDay,
                dailyWeather: d,
              )),
        ],
      ],
    );
  }

  Widget _buildHourlyTab(bool isDay) {
    return controller.hourly.isEmpty
        ? Center(
            child: Text(
              "No hourly forecast available",
              style: TextStyle(
                color: isDay
                    ? Colors.black.withValues(alpha: 0.54)
                    : Colors.white.withValues(alpha: 0.54),
                fontSize: 15,
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, i) {
                    final h = controller.hourly[i];
                    return HourlyTile(
                      time: h.time,
                      temp: "${h.tempC.toStringAsFixed(1)}°C",
                      icon: h.icon,
                      humidity: h.humidity.toString(),
                      isDay: isDay,
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: controller.hourly.length,
                ),
              ),
            ],
          );
  }

  Widget _buildRawTab(bool isDay) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        const JsonEncoder.withIndent('  ').convert(
          controller.rawWeatherJson ?? {"message": "No Raw Data Loaded"},
        ),
        style: TextStyle(
          color: isDay ? Colors.black.withValues(alpha: 0.87) : Colors.white,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildMetarTab(bool isDay) {
    return controller.metar == null
        ? Center(
            child: Text(
              "No METAR loaded.\nSearch by ICAO (e.g., OPLA).",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDay
                    ? Colors.black.withValues(alpha: 0.54)
                    : Colors.white.withValues(alpha: 0.54),
                fontSize: 15,
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MetarTile(
                station: controller.metar!["station"] ?? "--",
                observed: controller.metar!["observed"] ?? "--",
                temp: "${controller.metar!["temp_c"] ?? "--"}°C",
                wind:
                    "${controller.metar!["wind_kph"] ?? "--"} km/h (${controller.metar!["wind_degrees"] ?? "--"}°)",
                visibility: "${controller.metar!["visibility_km"] ?? "--"} km",
                pressure: "${controller.metar!["pressure_hpa"] ?? "--"} hPa",
                humidity: "${controller.metar!["humidity"] ?? "--"}%",
                dewpoint: "${controller.metar!["dewpoint_c"] ?? "--"}°C",
                iconUrl: controller.metar!["icon"] ?? '',
                isDay: isDay,
              ),
            ],
          );
  }

  Widget _buildWindyTab() {
    if (windy == null) _updateWindy();
    if (windy == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: windy!);
  }
}
