// lib/screens/alerts_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_alert.dart';
import '../services/alert_storage_service.dart';
import '../services/notification_service.dart';
import '../utils/background_utils.dart';

class AlertsScreen extends StatefulWidget {
  final bool embedded;

  const AlertsScreen({super.key, this.embedded = false});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final AlertStorageService _storage = AlertStorageService();
  final TextEditingController _searchController = TextEditingController();
  List<WeatherAlert> _alerts = [];
  List<String> _subscribedCities = [];
  List<String> _customCities = [];
  bool _loading = true;

  // Track expanded alerts
  final Set<String> _expandedAlerts = {};

  // Alert thresholds (user configurable)
  double _tempHighThreshold = 45.0;
  double _tempLowThreshold = 5.0;
  double _windSpeedThreshold = 50.0;
  double _visibilityThreshold = 2.0;

  // Available cities for subscription
  final List<String> _defaultCities = [
    'Islamabad',
    'Rawalpindi',
    'Lahore',
    'Karachi',
    'Faisalabad',
    'Multan',
    'Peshawar',
    'Quetta',
    'Sialkot',
    'Gwadar',
    'Hyderabad',
    'Gujranwala',
    'Bahawalpur',
    'Sargodha',
    'Sukkur',
  ];

  List<String> get _allCities => [..._defaultCities, ..._customCities]..sort();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // Sync read status from cloud first (for reinstall persistence)
    await _storage.syncReadStatusFromCloud();

    // Clean up any existing duplicates first
    await _storage.removeDuplicates();

    final alerts = await _storage.getAlerts();
    final cities = await _storage.getSubscribedCities();
    final prefs = await SharedPreferences.getInstance();

    // Load custom cities
    final customCities = prefs.getStringList('custom_cities') ?? [];

    // Load thresholds
    final tempHigh = prefs.getDouble('threshold_temp_high') ?? 45.0;
    final tempLow = prefs.getDouble('threshold_temp_low') ?? 5.0;
    final wind = prefs.getDouble('threshold_wind') ?? 50.0;
    final visibility = prefs.getDouble('threshold_visibility') ?? 2.0;

    setState(() {
      _alerts = alerts;
      _subscribedCities = cities;
      _customCities = customCities;
      _tempHighThreshold = tempHigh;
      _tempLowThreshold = tempLow;
      _windSpeedThreshold = wind;
      _visibilityThreshold = visibility;
      _loading = false;
    });
  }

  Future<void> _saveThresholds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('threshold_temp_high', _tempHighThreshold);
    await prefs.setDouble('threshold_temp_low', _tempLowThreshold);
    await prefs.setDouble('threshold_wind', _windSpeedThreshold);
    await prefs.setDouble('threshold_visibility', _visibilityThreshold);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert settings saved!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _addCustomCity(String city) async {
    if (city.isEmpty) return;

    final trimmed = city.trim();
    final capitalized =
        trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();

    if (_allCities.contains(capitalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$capitalized is already in the list')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final customCities = [..._customCities, capitalized];
    await prefs.setStringList('custom_cities', customCities);

    // Auto-subscribe to the new city
    await _storage.subscribeToCity(capitalized);
    await NotificationService().subscribeToCity(capitalized);

    _searchController.clear();
    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$capitalized added and subscribed!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _removeCustomCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    final customCities = _customCities.where((c) => c != city).toList();
    await prefs.setStringList('custom_cities', customCities);

    // Unsubscribe from the city
    await _storage.unsubscribeFromCity(city);
    await NotificationService().unsubscribeFromCity(city);

    await _loadData();
  }

  Future<void> _toggleCitySubscription(String city) async {
    final notificationService = NotificationService();
    final isSubscribed = _subscribedCities.contains(city);

    if (isSubscribed) {
      await _storage.unsubscribeFromCity(city);
      await notificationService.unsubscribeFromCity(city);
    } else {
      await _storage.subscribeToCity(city);
      await notificationService.subscribeToCity(city);
    }

    await _loadData();
  }

  Future<void> _markAllAsRead() async {
    await _storage.markAllAsRead();
    await _loadData();
  }

  Future<void> _clearAllAlerts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Alerts'),
        content: const Text('Are you sure you want to delete all alerts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.clearAllAlerts();
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    const isDay = true; // You can make this dynamic based on time
    final fg = foregroundForCard(isDay);

    final content = Column(
      children: [
        if (!widget.embedded) _buildAppBar(fg, isDay),
        _buildTabBar(isDay),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAlertsTab(isDay),
                    _buildSubscriptionsTab(isDay),
                    _buildSettingsTab(isDay),
                  ],
                ),
        ),
      ],
    );

    // If embedded in another screen, return just the content
    if (widget.embedded) {
      return content;
    }

    // Otherwise return full Scaffold
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: dynamicGradient('clear', isDay),
        ),
        child: SafeArea(
          child: content,
        ),
      ),
    );
  }

  Widget _buildAppBar(Color fg, bool isDay) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios, color: fg),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              'Weather Alerts',
              style: TextStyle(
                color: fg,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_alerts.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: fg),
              onSelected: (value) {
                if (value == 'read') _markAllAsRead();
                if (value == 'clear') _clearAllAlerts();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'read',
                  child: Text('Mark all as read'),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear all alerts'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDay) {
    final fg = foregroundForCard(isDay);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardTint(isDay),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: fg,
        unselectedLabelColor: fg.withValues(alpha: 0.5),
        indicator: BoxDecoration(
          color: isDay
              ? Colors.white.withValues(alpha: 0.5)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications, size: 18),
                const SizedBox(width: 4),
                const Text('Alerts'),
                if (_alerts.where((a) => !a.isRead).isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_alerts.where((a) => !a.isRead).length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_city, size: 18),
                SizedBox(width: 4),
                Text('Cities'),
              ],
            ),
          ),
          const Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune, size: 18),
                SizedBox(width: 4),
                Text('Settings'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(bool isDay) {
    final fg = foregroundForCard(isDay);

    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 64,
              color: fg.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No alerts yet',
              style: TextStyle(
                color: fg.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Weather alerts will appear here',
              style: TextStyle(
                color: fg.withValues(alpha: 0.3),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _alerts.length,
        itemBuilder: (context, index) {
          final alert = _alerts[index];
          return _buildAlertCard(alert, isDay);
        },
      ),
    );
  }

  Widget _buildAlertCard(WeatherAlert alert, bool isDay) {
    final fg = foregroundForCard(isDay);
    final severityColor = _getSeverityColor(alert.severity);
    final isExpanded = _expandedAlerts.contains(alert.id);
    final isManualAlert = alert.data?['source'] == 'admin_portal';

    return Dismissible(
      key: Key(alert.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        await _storage.deleteAlert(alert.id);
        await _loadData();
      },
      child: GestureDetector(
        onTap: () async {
          // Toggle expanded state
          setState(() {
            if (isExpanded) {
              _expandedAlerts.remove(alert.id);
            } else {
              _expandedAlerts.add(alert.id);
            }
          });
          // Mark as read
          if (!alert.isRead) {
            await _storage.markAlertAsRead(alert.id);
            await _loadData();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardTint(isDay),
                  borderRadius: BorderRadius.circular(16),
                  border: Border(
                    left: BorderSide(color: severityColor, width: 4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source badge row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isManualAlert
                                ? Colors.purple.withValues(alpha: 0.15)
                                : Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isManualAlert
                                  ? Colors.purple.withValues(alpha: 0.3)
                                  : Colors.teal.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isManualAlert
                                    ? Icons.admin_panel_settings
                                    : Icons.auto_awesome,
                                size: 12,
                                color:
                                    isManualAlert ? Colors.purple : Colors.teal,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isManualAlert ? 'MANUAL' : 'AUTO',
                                style: TextStyle(
                                  color: isManualAlert
                                      ? Colors.purple
                                      : Colors.teal,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (!alert.isRead)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Header row (always visible)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.title,
                            style: TextStyle(
                              color: fg,
                              fontSize: 16,
                              fontWeight: alert.isRead
                                  ? FontWeight.w500
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: fg.withValues(alpha: 0.5),
                        ),
                      ],
                    ),

                    // Brief info (always visible)
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (alert.city != null) ...[
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: fg.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            alert.city!,
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: fg.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(alert.receivedAt),
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            (alert.severity ?? 'medium').toUpperCase(),
                            style: TextStyle(
                              color: severityColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Expanded content
                    if (isExpanded) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: fg.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Details',
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              alert.body.isNotEmpty
                                  ? alert.body
                                  : 'No additional details available.',
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.8),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            if (alert.data != null &&
                                alert.data!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildAlertMetadata(alert, fg),
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
    );
  }

  Widget _buildAlertMetadata(WeatherAlert alert, Color fg) {
    final data = alert.data!;
    final List<Widget> metaItems = [];

    if (data['type'] != null) {
      metaItems.add(_buildMetaItem(
          Icons.category, 'Type', _getAlertTypeLabel(data['type']), fg));
    }
    if (data['source'] != null) {
      metaItems.add(_buildMetaItem(
          Icons.source,
          'Source',
          data['source'] == 'admin_portal' ? 'Admin Portal' : data['source'],
          fg));
    }
    if (data['match_reason'] != null) {
      metaItems.add(_buildMetaItem(
          Icons.info_outline, 'Match', data['match_reason'], fg));
    }
    if (data['zone_name'] != null) {
      metaItems.add(_buildMetaItem(Icons.place, 'Zone', data['zone_name'], fg));
    }
    if (data['mode'] != null) {
      final modeLabel = data['mode'] == 'polygon' ? 'Custom Area' : 'Radius';
      metaItems.add(_buildMetaItem(Icons.radar, 'Coverage', modeLabel, fg));
    }

    if (metaItems.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: metaItems,
    );
  }

  Widget _buildMetaItem(IconData icon, String label, String value, Color fg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(
          '$label: $value',
          style: TextStyle(
            color: fg.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  String _getAlertTypeLabel(String type) {
    switch (type) {
      case 'rain':
        return '🌧️ Rain';
      case 'heat':
        return '🌡️ Heat';
      case 'cold':
        return '❄️ Cold';
      case 'storm':
        return '⛈️ Storm';
      case 'wind':
        return '💨 Wind';
      case 'fog':
        return '🌫️ Fog';
      case 'dust':
        return '🌪️ Dust';
      case 'snow':
        return '🌨️ Snow';
      default:
        return '⚠️ $type';
    }
  }

  Widget _buildSubscriptionsTab(bool isDay) {
    final fg = foregroundForCard(isDay);

    return Column(
      children: [
        // Search and Add City
        Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cardTint(isDay),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: fg),
                        decoration: InputDecoration(
                          hintText: 'Add a city...',
                          hintStyle:
                              TextStyle(color: fg.withValues(alpha: 0.5)),
                          border: InputBorder.none,
                          icon: Icon(Icons.search,
                              color: fg.withValues(alpha: 0.5)),
                        ),
                        onSubmitted: _addCustomCity,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle, color: fg),
                      onPressed: () => _addCustomCity(_searchController.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Info text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Toggle cities to receive weather alerts. Custom cities marked with ⭐',
            style: TextStyle(
              color: fg.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Cities List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _allCities.length,
            itemBuilder: (context, index) {
              final city = _allCities[index];
              final isSubscribed = _subscribedCities.contains(city);
              final isCustom = _customCities.contains(city);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: cardTint(isDay),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isCustom ? Icons.star : Icons.location_city,
                            color: isCustom
                                ? Colors.amber
                                : fg.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              city,
                              style: TextStyle(
                                color: fg,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isCustom)
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Colors.red.withValues(alpha: 0.7)),
                              onPressed: () => _removeCustomCity(city),
                              tooltip: 'Remove city',
                            ),
                          Switch(
                            value: isSubscribed,
                            onChanged: (_) => _toggleCitySubscription(city),
                            activeTrackColor:
                                Colors.green.withValues(alpha: 0.5),
                            activeThumbColor: Colors.green,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab(bool isDay) {
    final fg = foregroundForCard(isDay);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Custom Alert Thresholds',
            style: TextStyle(
              color: fg,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set when you want to receive weather alerts',
            style: TextStyle(
              color: fg.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),

          // Heat Alert
          _buildThresholdCard(
            isDay: isDay,
            icon: Icons.whatshot,
            iconColor: Colors.red,
            title: 'Extreme Heat Alert',
            subtitle: 'Alert when temperature exceeds',
            value: _tempHighThreshold,
            unit: '°C',
            min: 35,
            max: 55,
            onChanged: (v) => setState(() => _tempHighThreshold = v),
          ),
          const SizedBox(height: 12),

          // Cold Alert
          _buildThresholdCard(
            isDay: isDay,
            icon: Icons.ac_unit,
            iconColor: Colors.blue,
            title: 'Cold Weather Alert',
            subtitle: 'Alert when temperature drops below',
            value: _tempLowThreshold,
            unit: '°C',
            min: -10,
            max: 15,
            onChanged: (v) => setState(() => _tempLowThreshold = v),
          ),
          const SizedBox(height: 12),

          // Wind Alert
          _buildThresholdCard(
            isDay: isDay,
            icon: Icons.air,
            iconColor: Colors.teal,
            title: 'Strong Wind Alert',
            subtitle: 'Alert when wind speed exceeds',
            value: _windSpeedThreshold,
            unit: 'km/h',
            min: 20,
            max: 100,
            onChanged: (v) => setState(() => _windSpeedThreshold = v),
          ),
          const SizedBox(height: 12),

          // Visibility Alert
          _buildThresholdCard(
            isDay: isDay,
            icon: Icons.visibility_off,
            iconColor: Colors.grey,
            title: 'Low Visibility Alert',
            subtitle: 'Alert when visibility drops below',
            value: _visibilityThreshold,
            unit: 'km',
            min: 0.5,
            max: 10,
            onChanged: (v) => setState(() => _visibilityThreshold = v),
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveThresholds,
              icon: const Icon(Icons.save),
              label: const Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Info Card
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: fg, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'How Alerts Work',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Weather is checked every 30 minutes\n'
                      '• Alerts are sent for subscribed cities only\n'
                      '• Same alert won\'t repeat within 3 hours\n'
                      '• Works offline using local monitoring',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdCard({
    required bool isDay,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required double value,
    required String unit,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final fg = foregroundForCard(isDay);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardTint(isDay),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${value.toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: ((max - min) * 2).toInt(),
                activeColor: iconColor,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSeverityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'extreme':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.yellow.shade700;
      case 'low':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.day}/${time.month}/${time.year}';
  }
}
