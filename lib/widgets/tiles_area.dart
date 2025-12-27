// lib/widgets/tiles_area.dart - 3 TILES PER ROW

import 'package:flutter/material.dart';
import '../services/weather_controller.dart';
import '../services/settings_service.dart';
import '../utils/feels_like_utils.dart';
import 'param_tile.dart';

/// Data class for a tile with icon
class TileData {
  final String label;
  final String value;
  final IconData icon;

  TileData({required this.label, required this.value, required this.icon});
}

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

    // 3 tiles per row
    for (int i = 0; i < tiles.length; i += 3) {
      final first = tiles[i];
      final second = (i + 1 < tiles.length) ? tiles[i + 1] : null;
      final third = (i + 2 < tiles.length) ? tiles[i + 2] : null;

      rows.add(
        Row(
          children: [
            Expanded(
              child: ParamTile(
                label: first.label,
                value: first.value,
                isDay: isDay,
                icon: first.icon,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : ParamTile(
                      label: second.label,
                      value: second.value,
                      isDay: isDay,
                      icon: second.icon,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: third == null
                  ? const SizedBox.shrink()
                  : ParamTile(
                      label: third.label,
                      value: third.value,
                      isDay: isDay,
                      icon: third.icon,
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
  List<TileData> _getTilesWithUnits(SettingsService settings) {
    final c = controller.current.value;
    if (c == null) return [];

    // Safe parsing for values that might be String or num
    double? parseDouble(dynamic v) {
      if (v == null || v == '--') return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? parseInt(dynamic v) {
      if (v == null || v == '--') return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    if (controller.metarApplied && controller.metar != null) {
      final m = controller.metar!;
      final windDeg = parseInt(m["wind_degrees"]);
      final metarWindDir =
          windDeg != null ? _mapWindDegreesToCardinal(windDeg) : "--";

      final dewC = parseDouble(m["dewpoint_c"]);
      final windKph = parseDouble(m["wind_kph"]);
      final tempC = parseDouble(m["temp_c"]);
      final humidity = parseDouble(m["humidity"]);

      final dewDisplay = dewC != null
          ? settings.convertTemperature(dewC).toStringAsFixed(1)
          : "--";
      final windDisplay = windKph != null
          ? settings.convertWindSpeedHybrid(windKph).toStringAsFixed(0)
          : "--";

      // Calculate feels like for METAR data
      String feelsLikeDisplay = "--";
      if (tempC != null) {
        final calculatedFeelsLike = calculateFeelsLike(
          tempC: tempC,
          humidity: humidity ?? 50,
          windKph: windKph ?? 0,
        );
        feelsLikeDisplay =
            settings.convertTemperature(calculatedFeelsLike).toStringAsFixed(1);
      }

      // Extract cloud cover percentage from raw_text
      final rawText = m["raw_text"]?.toString().toUpperCase() ?? "";
      final cloudCoverPercent = _extractCloudCoverPercent(rawText);

      // Get precipitation probability from today's forecast
      final todayForecast =
          controller.daily.isNotEmpty ? controller.daily.first : null;
      final precipChance = todayForecast?.precipitationProbability ?? 0;

      return [
        // Row 1: Feels Like | Humidity | Dew Point
        TileData(
            label: "Feels Like",
            value: "$feelsLikeDisplay${settings.temperatureSymbol}",
            icon: Icons.thermostat_outlined),
        TileData(
            label: "Humidity",
            value: "${m["humidity"] ?? "--"}%",
            icon: Icons.water_drop_outlined),
        TileData(
            label: "Dew Point",
            value: "$dewDisplay${settings.temperatureSymbol}",
            icon: Icons.opacity),
        // Row 2: Wind Speed | Wind Dir | Pressure
        TileData(
            label: "Wind Speed",
            value: "$windDisplay ${settings.windSymbolHybrid}",
            icon: Icons.air_rounded),
        TileData(
            label: "Wind Dir",
            value: metarWindDir,
            icon: Icons.explore_outlined),
        TileData(
            label: "Pressure",
            value: "${m["pressure_hpa"] ?? "--"} hPa",
            icon: Icons.speed_rounded),
        // Row 3: Visibility | Cloud Cover | Precip Chance
        TileData(
            label: "Visibility",
            value: "${m["visibility_km"] ?? "--"} km",
            icon: Icons.visibility_outlined),
        TileData(
            label: "Cloud Cover",
            value: "$cloudCoverPercent%",
            icon: Icons.cloud_outlined),
        TileData(
            label: "Precip Chance",
            value: "$precipChance%",
            icon: Icons.umbrella_outlined),
      ];
    }

    // Calculate feels like using wind chill / heat index
    // Rules: temp <= 15°C = wind chill, temp >= 25°C = heat index, else actual temp
    final calculatedFeelsLikeC = calculateFeelsLike(
      tempC: c.tempC,
      humidity: c.humidity.toDouble(),
      windKph: c.windKph,
    );
    final feelsLike =
        settings.convertTemperature(calculatedFeelsLikeC).toStringAsFixed(1);
    final dewPoint = c.dewpointC != null
        ? settings.convertTemperature(c.dewpointC!).toStringAsFixed(1)
        : '--';
    final windSpeed = c.gustKph != null
        ? settings.convertWindSpeedHybrid(c.gustKph!).toStringAsFixed(0)
        : '--';

    return [
      TileData(
          label: "Feels Like",
          value: "$feelsLike${settings.temperatureSymbol}",
          icon: Icons.thermostat_outlined),
      TileData(
          label: "Humidity",
          value: "${c.humidity}%",
          icon: Icons.water_drop_outlined),
      TileData(
          label: "Dew Point",
          value: "$dewPoint${settings.temperatureSymbol}",
          icon: Icons.opacity),
      TileData(
          label: "Pressure",
          value: "${c.pressureMb?.toStringAsFixed(0) ?? '--'} hPa",
          icon: Icons.speed_rounded),
      TileData(
          label: "Wind Speed",
          value: "$windSpeed ${settings.windSymbolHybrid}",
          icon: Icons.air_rounded),
      TileData(
          label: "Wind Dir",
          value: _mapWindDegreesToCardinal(c.windDeg),
          icon: Icons.explore_outlined),
      TileData(
          label: "UV Index",
          value: c.uvIndex?.toStringAsFixed(1) ?? '--',
          icon: Icons.wb_sunny_outlined),
      TileData(
          label: "Cloud Cover",
          value: "${c.cloudCover ?? '--'}%",
          icon: Icons.cloud_outlined),
      TileData(
          label: "Precipitation",
          value: "${c.precipitation?.toStringAsFixed(1) ?? '0'} mm",
          icon: Icons.umbrella_outlined),
    ];
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

  /// Extract cloud cover percentage from METAR raw text
  /// OVC = 100%, BKN = 75%, SCT = 50%, FEW = 25%, CLR/SKC = 0%
  int _extractCloudCoverPercent(String rawText) {
    // Cloud cover codes in order of priority (most coverage first)
    if (rawText.contains("OVC")) return 100; // Overcast (8/8 oktas)
    if (rawText.contains("BKN")) return 75; // Broken (5-7/8 oktas)
    if (rawText.contains("SCT")) return 50; // Scattered (3-4/8 oktas)
    if (rawText.contains("FEW")) return 25; // Few (1-2/8 oktas)
    if (rawText.contains("SKC") || rawText.contains("CLR")) return 0; // Clear
    if (rawText.contains("NSC")) return 0; // No significant clouds
    if (rawText.contains("NCD")) return 0; // No clouds detected
    if (rawText.contains("VV")) return 100; // Vertical visibility (fog/mist)
    return 0;
  }
}
