// lib/widgets/forecast_tile.dart - WITH FEELS LIKE HIGH/LOW

import 'package:flutter/material.dart';
import '../utils/background_utils.dart';
import '../models/daily_weather.dart';

class ForecastTile extends StatelessWidget {
  final String date;
  final String icon;
  final String condition;
  final String maxTemp;
  final String minTemp;
  final bool isDay;
  final DailyWeather? dailyWeather;
  // New optional parameters for feels like
  final double? feelsLikeHigh;
  final double? feelsLikeLow;

  const ForecastTile({
    super.key,
    required this.date,
    required this.icon,
    required this.condition,
    required this.maxTemp,
    required this.minTemp,
    this.isDay = true,
    this.dailyWeather,
    this.feelsLikeHigh,
    this.feelsLikeLow,
  });

  void _showDayDetails(BuildContext context) {
    if (dailyWeather == null) return;

    final d = dailyWeather!;
    // Get screen dimensions for responsive layout
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 360;
    final padding = isSmallScreen ? 14.0 : 20.0;

    // Consistent app theme colors (blue-based like rest of app)
    const fg = Colors.white;
    final cardBg = isDay
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.08);
    final dividerColor = Colors.white.withValues(alpha: 0.2);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDay
                ? [const Color(0xFF1976D2), const Color(0xFF1565C0)]
                : [const Color(0xFF1C1C1E), const Color(0xFF2C2C2E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header with date only (no duplicate temps)
              Center(
                child: Text(_formatDateDisplay(d.date),
                    style: TextStyle(
                        fontSize: isSmallScreen ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color: fg)),
              ),
              const SizedBox(height: 12),

              // Day/Night Weather Cards (these show the temps)
              Row(
                children: [
                  // Daytime Card
                  Expanded(
                    child: _buildDayNightCard(
                      context: context,
                      title: "Day",
                      icon: d.dayIcon ?? icon,
                      condition: d.dayCondition ?? d.condition,
                      temp: d.dayHighTemp ?? d.maxTemp,
                      isHigh: true,
                      sunTime: d.sunrise,
                      fg: fg,
                      cardBg: cardBg,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Nighttime Card
                  Expanded(
                    child: _buildDayNightCard(
                      context: context,
                      title: "Night",
                      icon: d.nightIcon ?? icon,
                      condition: d.nightCondition ?? d.condition,
                      temp: d.nightLowTemp ?? d.minTemp,
                      isHigh: false,
                      sunTime: d.sunset,
                      fg: fg,
                      cardBg: cardBg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: dividerColor),
              const SizedBox(height: 8),

              // Feels Like Section
              if (feelsLikeHigh != null || feelsLikeLow != null) ...[
                Text(
                  "Feels Like",
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    color: fg.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildFeelsLikeTile(
                        context: context,
                        label: "High",
                        value: feelsLikeHigh != null
                            ? "${feelsLikeHigh!.toStringAsFixed(0)}°"
                            : "--",
                        accentColor: Colors.orange[400]!,
                        fg: fg,
                        cardBg: cardBg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFeelsLikeTile(
                        context: context,
                        label: "Low",
                        value: feelsLikeLow != null
                            ? "${feelsLikeLow!.toStringAsFixed(0)}°"
                            : "--",
                        accentColor: Colors.blue[300]!,
                        fg: fg,
                        cardBg: cardBg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Parameters Grid - Dynamic columns based on screen width
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / 3 - 8;
                  final itemCount = _getDetailItems(d, fg, cardBg).length;
                  if (itemCount == 0) return const SizedBox.shrink();

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _getDetailItems(d, fg, cardBg).map((item) {
                      return SizedBox(
                        width: itemWidth,
                        child: item,
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Get list of detail items for the grid
  List<Widget> _getDetailItems(DailyWeather d, Color fg, Color cardBg) {
    final items = <Widget>[];
    if (d.uvIndexMax != null) {
      items.add(_buildDetailItem(Icons.wb_sunny_outlined, "UV",
          d.uvIndexMax!.toStringAsFixed(1), fg, cardBg,
          iconColor: Colors.amber));
    }
    if (d.precipitationProbability != null) {
      // Use cyan color for rain drop icon - visible on blue background
      items.add(_buildDetailItem(Icons.water_drop, "Rain",
          "${d.precipitationProbability}%", fg, cardBg,
          iconColor: Colors.cyan[200]));
    }
    if (d.precipitationSum != null) {
      items.add(_buildDetailItem(Icons.grain, "Precip",
          "${d.precipitationSum!.toStringAsFixed(1)}mm", fg, cardBg,
          iconColor: Colors.lightBlue[200]));
    }
    if (d.windGustsMax != null) {
      items.add(_buildDetailItem(Icons.air, "Gusts",
          "${d.windGustsMax!.toStringAsFixed(0)}km/h", fg, cardBg));
    }
    if (d.windDirectionDominant != null) {
      items.add(_buildDetailItem(Icons.explore, "Wind",
          _windDirToCardinal(d.windDirectionDominant!), fg, cardBg));
    }
    return items;
  }

  /// Build a card for day or night weather
  Widget _buildDayNightCard({
    required BuildContext context,
    required String title,
    required String icon,
    required String condition,
    required double temp,
    required bool isHigh,
    required String sunTime,
    required Color fg,
    required Color cardBg,
  }) {
    final accentColor = isHigh ? Colors.orange[400]! : Colors.blue[300]!;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final iconSize = isSmallScreen ? 32.0 : 40.0;
    final tempFontSize = isSmallScreen ? 20.0 : 24.0;
    final sunIcon = isHigh ? "☀️" : "🌙";

    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
              Flexible(
                child: Text(
                  "$sunIcon $sunTime",
                  style: TextStyle(
                    fontSize: isSmallScreen ? 9 : 10,
                    color: fg.withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Icon and Temp
          Row(
            children: [
              // Add light background to make rain drops visible on blue gradient
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.network(
                  icon,
                  width: iconSize,
                  height: iconSize,
                  errorBuilder: (_, __, ___) => Icon(
                      isHigh ? Icons.wb_sunny : Icons.nightlight_round,
                      size: iconSize,
                      color: accentColor),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "${temp.toStringAsFixed(0)}°",
                  style: TextStyle(
                    fontSize: tempFontSize,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Condition
          Text(
            condition,
            style: TextStyle(
              fontSize: isSmallScreen ? 10 : 11,
              color: fg.withValues(alpha: 0.8),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFeelsLikeTile(
      {required BuildContext context,
      required String label,
      required String value,
      required Color accentColor,
      required Color fg,
      required Color cardBg}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 12,
        vertical: isSmallScreen ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.thermostat,
                    size: isSmallScreen ? 14 : 16, color: accentColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 11 : 12,
                    color: fg.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 15,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(
      IconData icon, String label, String value, Color fg, Color cardBg,
      {Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor ?? fg.withValues(alpha: 0.8)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                style:
                    TextStyle(fontSize: 9, color: fg.withValues(alpha: 0.7))),
          ),
        ],
      ),
    );
  }

  String _formatDateDisplay(String date) {
    try {
      final dt = DateTime.parse(date);
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));

      if (dt.day == now.day && dt.month == now.month) return "Today";
      if (dt.day == tomorrow.day && dt.month == tomorrow.month)
        return "Tomorrow";

      const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
      const months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec"
      ];
      return "${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}";
    } catch (_) {
      return date;
    }
  }

  String _windDirToCardinal(int degrees) {
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
    final index = (((degrees % 360) / 22.5) + 0.5).floor() % 16;
    return directions[index];
  }

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(isDay);
    final tint = cardTint(isDay);

    // PERFORMANCE: Removed BackdropFilter - too expensive for 7 tiles
    return GestureDetector(
      onTap: () => _showDayDetails(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Image.network(
              icon,
              width: 44,
              height: 44,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.cloud, size: 40, color: fg.withValues(alpha: 0.6)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatDateDisplay(date),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: fg)),
                  Text(condition,
                      style: TextStyle(
                          fontSize: 12, color: fg.withValues(alpha: 0.7)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("$maxTemp°",
                    style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text("$minTemp°",
                    style: TextStyle(color: Colors.blue[400], fontSize: 13)),
              ],
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                color: fg.withValues(alpha: 0.4), size: 18),
          ],
        ),
      ),
    );
  }
}
