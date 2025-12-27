// lib/widgets/wu_widget.dart

import 'dart:math' show cos, sqrt, atan2, sin, pi;
import 'package:flutter/material.dart';
import '../wu_stations.dart';
import '../services/wu_service.dart';
import 'param_tile.dart';
import '../utils/background_utils.dart';

class WuWidget extends StatefulWidget {
  final bool isDay;
  final bool isActive; // Only load data when tab is active
  final Function(Map<String, dynamic>? data)? onDataLoaded;
  final String? city; // City from main app to sync with
  final double? userLat; // User's current latitude
  final double? userLon; // User's current longitude

  const WuWidget(
      {super.key,
      required this.isDay,
      this.isActive = false,
      this.onDataLoaded,
      this.city,
      this.userLat,
      this.userLon});

  @override
  State<WuWidget> createState() => _WuWidgetState();
}

class _WuWidgetState extends State<WuWidget> {
  String? _selectedCity;
  String? _selectedStationId;
  Map<String, dynamic>? _currentData;
  bool _loading = false;
  String? _error;
  // Store station info with location for dropdown display
  Map<String, Map<String, dynamic>> _stationInfo = {};
  // Track if user is within 5km radius of a station
  bool _isWithinRadius = false;
  // ignore: unused_field
  String? _nearbyStationId;
  double? _nearbyStationDistance;
  // Track if we're scanning for nearby stations
  bool _scanningForNearby = false;
  bool _hasScannedForLocation = false;
  // Track if data has been loaded at least once (for lazy loading)
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _initializeCity();
    // Only load if tab is active (lazy loading)
    if (widget.isActive && widget.userLat != null && widget.userLon != null) {
      _scanForNearbyStation();
    }
  }

  @override
  void didUpdateWidget(WuWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If tab became active and hasn't loaded yet, load now
    if (widget.isActive && !oldWidget.isActive && !_hasLoadedOnce) {
      if (widget.userLat != null &&
          widget.userLon != null &&
          !_hasScannedForLocation) {
        _scanForNearbyStation();
      } else if (_selectedCity != null && _currentData == null) {
        _autoLoadFirstStation(_selectedCity!);
      }
    }

    // If city prop changed, update selection
    if (oldWidget.city != widget.city && widget.city != null) {
      _syncCityFromProp();
    }
    // If user location changed (e.g., current location button pressed), rescan
    if ((oldWidget.userLat != widget.userLat ||
            oldWidget.userLon != widget.userLon) &&
        widget.userLat != null &&
        widget.userLon != null) {
      _hasScannedForLocation = false;
      _scanForNearbyStation();
    }
  }

  void _initializeCity() {
    if (widget.city != null) {
      _syncCityFromProp();
    } else if (wuStationsByCity.isNotEmpty) {
      _selectedCity = wuStationsByCity.keys.first;
    }
  }

  /// Sync the selected city from the passed prop
  /// Matches the city name to available WU station cities
  void _syncCityFromProp() {
    final cityProp = widget.city;
    if (cityProp == null || cityProp.isEmpty) return;

    final cityLower = cityProp.toLowerCase();

    // Find matching city in wuStationsByCity
    for (final availableCity in wuStationsByCity.keys) {
      if (availableCity.toLowerCase() == cityLower ||
          cityLower.contains(availableCity.toLowerCase()) ||
          availableCity.toLowerCase().contains(cityLower)) {
        if (_selectedCity != availableCity) {
          setState(() {
            _selectedCity = availableCity;
            _selectedStationId = null; // Reset station selection
            _currentData = null;
          });
          // Auto-load the first station for this city
          _autoLoadFirstStation(availableCity);
        }
        return;
      }
    }

    // If no match found, keep current selection or use first available
    if (_selectedCity == null && wuStationsByCity.isNotEmpty) {
      _selectedCity = wuStationsByCity.keys.first;
    }
  }

  /// Auto-load the first station for a given city
  Future<void> _autoLoadFirstStation(String city) async {
    // Only load if tab is active (lazy loading)
    if (!widget.isActive) return;

    final stations = wuStationsByCity[city];
    if (stations == null || stations.isEmpty) return;

    final firstStationId = stations.first['id'];
    if (firstStationId != null) {
      setState(() {
        _selectedStationId = firstStationId;
      });
      await _loadStation(firstStationId);
    }
  }

  Future<void> _loadStation(String id) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentData = null;
    });

    final res = await fetchWUCurrentByStation(id);
    if (!mounted) return;

    setState(() {
      _loading = false;
      _hasLoadedOnce = true; // Mark as loaded
      if (res == null) _error = "No data found for $id";
      _currentData = res;
      // Store station info for dropdown display
      if (res != null) {
        _stationInfo[id] = {
          'lat': res['lat'],
          'lon': res['lon'],
          'neighborhood': res['neighborhood'],
        };
      }
    });

    if (widget.onDataLoaded != null) {
      widget.onDataLoaded!(res);
    }

    // Check if user is within 5km radius of this station
    _checkProximityToStation(id, res);
  }

  /// Calculate distance between two coordinates using Haversine formula
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

  double _toRadians(double deg) => deg * pi / 180;

  /// Check if user is within 5km of any loaded station
  void _checkProximityToStation(
      String stationId, Map<String, dynamic>? stationData) {
    if (widget.userLat == null || widget.userLon == null || stationData == null)
      return;

    final stationLat = stationData['lat'] as num?;
    final stationLon = stationData['lon'] as num?;

    if (stationLat == null || stationLon == null) return;

    final distance = _calculateDistance(
      widget.userLat!,
      widget.userLon!,
      stationLat.toDouble(),
      stationLon.toDouble(),
    );

    if (distance <= 5.0) {
      setState(() {
        _isWithinRadius = true;
        _nearbyStationId = stationId;
        _nearbyStationDistance = distance;
      });
    }
  }

  /// Scan stations in the matched city to find nearest one within 5km
  /// Only scans the matched city to avoid excessive API calls
  Future<void> _scanForNearbyStation() async {
    // Only scan if tab is active (lazy loading)
    if (!widget.isActive) return;
    if (widget.userLat == null || widget.userLon == null) return;
    if (_hasScannedForLocation) return;
    if (_scanningForNearby) return;

    // First, check if we have a matching city
    String? matchedCity;
    if (widget.city != null) {
      final cityLower = widget.city!.toLowerCase();
      for (final availableCity in wuStationsByCity.keys) {
        if (availableCity.toLowerCase() == cityLower ||
            cityLower.contains(availableCity.toLowerCase()) ||
            availableCity.toLowerCase().contains(cityLower)) {
          matchedCity = availableCity;
          break;
        }
      }
    }

    // Don't scan all cities - too many API calls. Only scan if we have a matched city.
    if (matchedCity == null) {
      _hasScannedForLocation = true;
      // Just use the first city/station without scanning
      if (_selectedCity == null && wuStationsByCity.isNotEmpty) {
        _selectedCity = wuStationsByCity.keys.first;
        _autoLoadFirstStation(_selectedCity!);
      }
      return;
    }

    final stations = wuStationsByCity[matchedCity];
    if (stations == null || stations.isEmpty) {
      _hasScannedForLocation = true;
      return;
    }

    // Limit scanning to max 3 stations to conserve API calls
    final stationsToScan = stations.take(3).toList();

    setState(() {
      _scanningForNearby = true;
      _loading = true;
    });
    _hasScannedForLocation = true;

    double? minDistance;
    String? nearestStationId;
    Map<String, dynamic>? nearestStationData;

    for (final station in stationsToScan) {
      final stationId = station['id'];
      if (stationId == null) continue;

      // Fetch station data to get coordinates
      final stationData = await fetchWUCurrentByStation(stationId);
      if (!mounted) return;

      if (stationData != null) {
        // Store station info for later use
        _stationInfo[stationId] = {
          'lat': stationData['lat'],
          'lon': stationData['lon'],
          'neighborhood': stationData['neighborhood'],
        };

        final stationLat = stationData['lat'] as num?;
        final stationLon = stationData['lon'] as num?;

        if (stationLat != null && stationLon != null) {
          final distance = _calculateDistance(
            widget.userLat!,
            widget.userLon!,
            stationLat.toDouble(),
            stationLon.toDouble(),
          );

          if (distance <= 5.0 &&
              (minDistance == null || distance < minDistance)) {
            minDistance = distance;
            nearestStationId = stationId;
            nearestStationData = stationData;
          }
        }
      }

      // If we found a station within 5km, stop scanning
      if (nearestStationId != null) break;
    }

    if (!mounted) return;

    if (nearestStationId != null && nearestStationData != null) {
      setState(() {
        _isWithinRadius = true;
        _nearbyStationId = nearestStationId;
        _nearbyStationDistance = minDistance;
        _selectedCity = matchedCity;
        _selectedStationId = nearestStationId;
        _currentData = nearestStationData;
        _scanningForNearby = false;
        _loading = false;
      });

      if (widget.onDataLoaded != null) {
        widget.onDataLoaded!(nearestStationData);
      }
    } else {
      // No nearby station found within 5km, just load the first station
      setState(() {
        _scanningForNearby = false;
        _selectedCity = matchedCity;
      });
      _autoLoadFirstStation(matchedCity);
    }
  }

  Widget _buildDropdown(
      String label,
      String? value,
      List<DropdownMenuItem<String>> items,
      Function(String? v) onChanged,
      bool isDay) {
    final fg = foregroundForCard(isDay);
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: fg, fontSize: 14),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
        filled: true,
        fillColor: cardTint(isDay).withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      dropdownColor: cardTint(isDay).withValues(alpha: 0.9),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildMainCard(bool isDay) {
    final c = _currentData!;
    final fg = foregroundForCard(isDay);
    final tint = cardTint(isDay);

    final cityName = _selectedCity ?? '--';
    final stationId = c['station'] ?? _selectedStationId ?? '--';
    final temp = "${c['temp_c'] ?? '--'}°C";
    final feelsLike =
        "Feels like ${c['temp_c'] ?? '--'}°C"; // Using same temp as feels like since WU doesn't provide it

    // Determine weather icon - show rain if rain rate > 0, otherwise borrow from main card
    final rainRate = c['rain_rate'];
    final hasRain = rainRate != null && rainRate is num && rainRate > 0;
    final weatherIcon = hasRain
        ? Icons.water_drop_rounded
        : (isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round);
    final iconColor = hasRain
        ? Colors.blue[400]!
        : (isDay ? Colors.orange[400]! : Colors.amber[300]!);

    // Build proximity info text if within radius
    final String? proximityText =
        _isWithinRadius && _nearbyStationDistance != null
            ? '${_nearbyStationDistance!.toStringAsFixed(1)} km away'
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDay ? 0.05 : 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Weather Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                weatherIcon,
                size: 32,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 14),
            // City and Station Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          cityName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: fg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isWithinRadius) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.near_me,
                                  size: 10, color: Colors.green[400]),
                              const SizedBox(width: 3),
                              Text(
                                'Nearby',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    proximityText != null
                        ? '$stationId • $proximityText'
                        : stationId,
                    style: TextStyle(
                      fontSize: 11,
                      color: fg.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            // Temperature and Feels Like
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  temp,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                Text(
                  feelsLike,
                  style: TextStyle(
                    fontSize: 11,
                    color: fg.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTilesArea(bool isDay) {
    if (_currentData == null) return const SizedBox.shrink();
    final c = _currentData!;

    // Custom tile order with icons
    final tileRows = [
      // Row 1: Humidity | Dew Point
      [
        {
          "label": "Humidity",
          "value": "${c['humidity'] ?? '--'}%",
          "icon": Icons.water_drop_outlined
        },
        {
          "label": "Dew Point",
          "value": "${c['dewpoint_c'] ?? '--'}°C",
          "icon": Icons.thermostat_outlined
        },
      ],
      // Row 2: Rain Total | Rain Rate
      [
        {
          "label": "Rain Total",
          "value": "${c['rain_total'] ?? '--'} mm",
          "icon": Icons.umbrella_outlined
        },
        {
          "label": "Rain Rate",
          "value": "${c['rain_rate'] ?? '--'} mm/hr",
          "icon": Icons.grain_outlined
        },
      ],
      // Row 3: Wind Speed | Wind Gust
      [
        {
          "label": "Wind Speed",
          "value": "${c['wind_kph'] ?? '--'} km/h",
          "icon": Icons.air_outlined
        },
        {
          "label": "Wind Gust",
          "value": "${c['wind_kph'] ?? '--'} km/h",
          "icon": Icons.storm_outlined
        },
      ],
      // Row 4: Wind Dir | Pressure
      [
        {
          "label": "Wind Dir",
          "value": "${c['wind_degrees'] ?? '--'}°",
          "icon": Icons.explore_outlined
        },
        {
          "label": "Pressure",
          "value": "${c['pressure_hpa'] ?? '--'} hPa",
          "icon": Icons.speed_outlined
        },
      ],
    ];

    final List<Widget> rows = [];

    for (var tileRow in tileRows) {
      rows.add(
        Row(
          children: [
            Expanded(
              child: ParamTile(
                label: tileRow[0]["label"] as String,
                value: tileRow[0]["value"] as String,
                isDay: isDay,
                icon: tileRow[0]["icon"] as IconData,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ParamTile(
                label: tileRow[1]["label"] as String,
                value: tileRow[1]["value"] as String,
                isDay: isDay,
                icon: tileRow[1]["icon"] as IconData,
              ),
            ),
          ],
        ),
      );
      rows.add(const SizedBox(height: 12));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: rows.take(rows.length - 1).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stations =
        _selectedCity == null ? [] : wuStationsByCity[_selectedCity] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text("Weather Underground PWS",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: foregroundForCard(widget.isDay))),
          ),
          const SizedBox(height: 22),
          // Hide City dropdown when within radius
          if (!_isWithinRadius)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: _buildDropdown(
                  "City",
                  _selectedCity,
                  wuStationsByCity.keys
                      .map<DropdownMenuItem<String>>((c) =>
                          DropdownMenuItem<String>(
                              value: c,
                              child: Text(c,
                                  style: TextStyle(
                                      color: foregroundForCard(widget.isDay)))))
                      .toList(), (v) {
                setState(() {
                  _selectedCity = v;
                  _selectedStationId = null;
                  _currentData = null;
                  _error = null;
                });
              }, widget.isDay),
            ),
          if (!_isWithinRadius) const SizedBox(height: 22),
          // Hide Station ID dropdown when within radius
          if (_selectedCity != null && !_isWithinRadius)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: _buildDropdown(
                  "Station ID",
                  _selectedStationId,
                  stations.map<DropdownMenuItem<String>>(
                    (s) {
                      final stationId = s["id"]!;
                      final info = _stationInfo[stationId];
                      String displayText = s["name"] ?? stationId;
                      // Add location info if available
                      if (info != null &&
                          info['neighborhood'] != null &&
                          info['neighborhood'] != '--') {
                        displayText =
                            '${s["name"] ?? stationId} (${info['neighborhood']})';
                      } else if (info != null &&
                          info['lat'] != null &&
                          info['lon'] != null) {
                        final lat =
                            (info['lat'] as num?)?.toStringAsFixed(2) ?? '--';
                        final lon =
                            (info['lon'] as num?)?.toStringAsFixed(2) ?? '--';
                        displayText = '${s["name"] ?? stationId} ($lat, $lon)';
                      }
                      return DropdownMenuItem<String>(
                        value: stationId,
                        child: Text(displayText,
                            style: TextStyle(
                                color: foregroundForCard(widget.isDay),
                                fontSize: 13)),
                      );
                    },
                  ).toList(), (v) {
                setState(() => _selectedStationId = v);
                if (v != null) _loadStation(v);
              }, widget.isDay),
            ),
          // Show "Switch Station" button when within radius to allow manual selection
          if (_isWithinRadius)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isWithinRadius = false;
                    _nearbyStationId = null;
                    _nearbyStationDistance = null;
                  });
                },
                icon: Icon(Icons.swap_horiz,
                    size: 18,
                    color:
                        foregroundForCard(widget.isDay).withValues(alpha: 0.7)),
                label: Text(
                  'Switch Station',
                  style: TextStyle(
                    color:
                        foregroundForCard(widget.isDay).withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 28),
          if (_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (_scanningForNearby) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Scanning for nearby stations...',
                      style: TextStyle(
                        color: foregroundForCard(widget.isDay)
                            .withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (_error != null)
            Center(
                child: Text(_error!, style: const TextStyle(color: Colors.red)))
          else if (_currentData != null) ...[
            _buildMainCard(widget.isDay),
            const SizedBox(height: 24),
            _buildTilesArea(widget.isDay),
          ],
        ],
      ),
    );
  }
}
