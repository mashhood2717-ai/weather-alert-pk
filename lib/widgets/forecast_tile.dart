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
    final fg = isDay ? Colors.black87 : Colors.white;
    final bgColor = isDay
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.grey[900]!.withValues(alpha: 0.95);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Image.network(icon,
                    width: 56,
                    height: 56,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.cloud, size: 56, color: fg)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_formatDateDisplay(d.date),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: fg)),
                      Text(d.condition,
                          style: TextStyle(
                              fontSize: 14, color: fg.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${d.maxTemp.toStringAsFixed(0)}°",
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700])),
                    Text("${d.minTemp.toStringAsFixed(0)}°",
                        style:
                            TextStyle(fontSize: 20, color: Colors.blue[600])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Feels Like Section - NEW
            if (feelsLikeHigh != null || feelsLikeLow != null) ...[
              Text(
                "Feels Like",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildFeelsLikeTile(
                      "High",
                      feelsLikeHigh != null
                          ? "${feelsLikeHigh!.toStringAsFixed(0)}°C"
                          : "--",
                      Colors.orange[700]!,
                      fg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeelsLikeTile(
                      "Low",
                      feelsLikeLow != null
                          ? "${feelsLikeLow!.toStringAsFixed(0)}°C"
                          : "--",
                      Colors.blue[600]!,
                      fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Parameters Grid
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildDetailItem(Icons.wb_sunny, "Sunrise", d.sunrise, fg),
                _buildDetailItem(
                    Icons.nightlight_round, "Sunset", d.sunset, fg),
                if (d.uvIndexMax != null)
                  _buildDetailItem(Icons.wb_sunny_outlined, "UV Index",
                      d.uvIndexMax!.toStringAsFixed(1), fg),
                if (d.precipitationProbability != null)
                  _buildDetailItem(Icons.water_drop, "Rain Chance",
                      "${d.precipitationProbability}%", fg),
                if (d.precipitationSum != null)
                  _buildDetailItem(Icons.grain, "Precipitation",
                      "${d.precipitationSum!.toStringAsFixed(1)} mm", fg),
                if (d.windGustsMax != null)
                  _buildDetailItem(Icons.air, "Wind Gusts",
                      "${d.windGustsMax!.toStringAsFixed(0)} km/h", fg),
                if (d.windDirectionDominant != null)
                  _buildDetailItem(Icons.explore, "Wind Dir",
                      _windDirToCardinal(d.windDirectionDominant!), fg),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFeelsLikeTile(
      String label, String value, Color accentColor, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.thermostat, size: 18, color: accentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: fg.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value, Color fg) {
    return Container(
      width: 95,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: fg.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: fg)),
          Text(label,
              style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.6))),
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
