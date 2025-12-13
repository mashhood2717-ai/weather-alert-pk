// lib/widgets/wu_widget.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../wu_stations.dart';
import '../services/wu_service.dart';
import 'param_tile.dart';
import '../utils/background_utils.dart';

class WuWidget extends StatefulWidget {
  final bool isDay;
  final Function(Map<String, dynamic>? data)? onDataLoaded;
  final String? city; // City from main app to sync with

  const WuWidget(
      {super.key, required this.isDay, this.onDataLoaded, this.city});

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

  @override
  void initState() {
    super.initState();
    _initializeCity();
  }

  @override
  void didUpdateWidget(WuWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If city prop changed, update selection
    if (oldWidget.city != widget.city && widget.city != null) {
      _syncCityFromProp();
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
        }
        return;
      }
    }

    // If no match found, keep current selection or use first available
    if (_selectedCity == null && wuStationsByCity.isNotEmpty) {
      _selectedCity = wuStationsByCity.keys.first;
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
        labelStyle: TextStyle(color: fg),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cityName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Station: $stationId",
                  style: TextStyle(
                    fontSize: 13,
                    color: fg.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  temp,
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feelsLike,
                  style: TextStyle(
                    fontSize: 13,
                    color: fg.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTilesArea(bool isDay) {
    if (_currentData == null) return const SizedBox.shrink();
    final c = _currentData!;

    // Custom tile order as requested
    final tileRows = [
      // Row 1: Humidity | Dew Point
      [
        {"label": "Humidity", "value": "${c['humidity'] ?? '--'}%"},
        {"label": "Dew Point", "value": "${c['dewpoint_c'] ?? '--'}°C"},
      ],
      // Row 2: Rain Total | Rain Rate
      [
        {"label": "Rain Total", "value": "${c['rain_total'] ?? '--'} mm"},
        {"label": "Rain Rate", "value": "${c['rain_rate'] ?? '--'} mm/hr"},
      ],
      // Row 3: Wind Speed | Wind Gust (using wind speed for gust as WU doesn't provide gust separately)
      [
        {"label": "Wind Speed", "value": "${c['wind_kph'] ?? '--'} km/h"},
        {"label": "Wind Gust", "value": "${c['wind_kph'] ?? '--'} km/h"},
      ],
      // Row 4: Wind Dir | Pressure
      [
        {"label": "Wind Dir", "value": "${c['wind_degrees'] ?? '--'}°"},
        {"label": "Pressure", "value": "${c['pressure_hpa'] ?? '--'} hPa"},
      ],
    ];

    final List<Widget> rows = [];

    for (var tileRow in tileRows) {
      rows.add(
        Row(
          children: [
            Expanded(
              child: ParamTile(
                label: tileRow[0]["label"]!,
                value: tileRow[0]["value"]!,
                isDay: isDay,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ParamTile(
                label: tileRow[1]["label"]!,
                value: tileRow[1]["value"]!,
                isDay: isDay,
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
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
          const SizedBox(height: 14),
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
          const SizedBox(height: 14),
          if (_selectedCity != null)
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
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(
                child: Text(_error!, style: const TextStyle(color: Colors.red)))
          else if (_currentData != null) ...[
            _buildMainCard(widget.isDay),
            const SizedBox(height: 16),
            _buildTilesArea(widget.isDay),
          ],
        ],
      ),
    );
  }
}
