// lib/widgets/tiles_area.dart - 3 TILES PER ROW

import 'package:flutter/material.dart';
import '../services/weather_controller.dart';
import '../services/settings_service.dart';
import 'param_tile.dart';

class TilesArea extends StatelessWidget {
  final WeatherController controller;

  const TilesArea({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();
    final tiles = _getTilesWithUnits(settings);
    final isDay = (controller.current.value?.isDay ?? 1) == 1;

    if (tiles.isEmpty) return const SizedBox.shrink();

    final List<Widget> rows = [];
    final entries = tiles.entries.toList();

    // 3 tiles per row
    for (int i = 0; i < entries.length; i += 3) {
      final first = entries[i];
      final second = (i + 1 < entries.length) ? entries[i + 1] : null;
      final third = (i + 2 < entries.length) ? entries[i + 2] : null;

      rows.add(
        Row(
          children: [
            Expanded(
              child: ParamTile(
                label: first.key,
                value: first.value,
                isDay: isDay,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : ParamTile(
                      label: second.key,
                      value: second.value,
                      isDay: isDay,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: third == null
                  ? const SizedBox.shrink()
                  : ParamTile(
                      label: third.key,
                      value: third.value,
                      isDay: isDay,
                    ),
            ),
          ],
        ),
      );

      rows.add(const SizedBox(height: 8));
    }

    return Column(children: rows.take(rows.length - 1).toList());
  }

  /// Get tiles with unit conversion applied
  Map<String, String> _getTilesWithUnits(SettingsService settings) {
    final c = controller.current.value;
    if (c == null) return {};

    if (controller.metarApplied && controller.metar != null) {
      final m = controller.metar!;
      final windDeg = m["wind_degrees"];
      final metarWindDir = windDeg != null
          ? _mapWindDegreesToCardinal((windDeg as num).toInt())
          : "--";

      final dewC = m["dewpoint_c"];
      final windKph = m["wind_kph"];

      final dewDisplay = dewC != null
          ? settings
              .convertTemperature((dewC as num).toDouble())
              .toStringAsFixed(1)
          : "--";
      final windDisplay = windKph != null
          ? settings
              .convertWindSpeedHybrid((windKph as num).toDouble())
              .toStringAsFixed(0)
          : "--";

      return {
        "Humidity": "${m["humidity"] ?? "--"}%",
        "Dew Point": "$dewDisplay${settings.temperatureSymbol}",
        "Pressure": "${m["pressure_hpa"] ?? "--"} hPa",
        "Visibility": "${m["visibility_km"] ?? "--"} km",
        "Wind Speed": "$windDisplay ${settings.windSymbolHybrid}",
        "Wind Dir": metarWindDir,
      };
    }

    final feelsLike = c.feelsLikeC != null
        ? settings.convertTemperature(c.feelsLikeC!).toStringAsFixed(1)
        : '--';
    final dewPoint = c.dewpointC != null
        ? settings.convertTemperature(c.dewpointC!).toStringAsFixed(1)
        : '--';
    final windSpeed = c.gustKph != null
        ? settings.convertWindSpeedHybrid(c.gustKph!).toStringAsFixed(0)
        : '--';

    return {
      "Feels Like": "$feelsLike${settings.temperatureSymbol}",
      "Humidity": "${c.humidity}%",
      "Dew Point": "$dewPoint${settings.temperatureSymbol}",
      "Pressure": "${c.pressureMb?.toStringAsFixed(0) ?? '--'} hPa",
      "Wind Speed": "$windSpeed ${settings.windSymbolHybrid}",
      "Wind Dir": _mapWindDegreesToCardinal(c.windDeg),
      "UV Index": "${c.uvIndex?.toStringAsFixed(1) ?? '--'}",
      "Cloud Cover": "${c.cloudCover ?? '--'}%",
      "Precipitation": "${c.precipitation?.toStringAsFixed(1) ?? '0'} mm",
    };
  }

  String _mapWindDegreesToCardinal(int? degrees) {
    if (degrees == null) return '--';
    const directions = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSW',
      'SW',
      'WSW',
      'W',
      'WNW',
      'NW',
      'NNW'
    ];
    final index = ((degrees + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }
}
