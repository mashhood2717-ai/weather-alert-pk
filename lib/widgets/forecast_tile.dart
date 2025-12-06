// lib/widgets/forecast_tile.dart

import 'dart:ui';
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
  final DailyWeather? dailyWeather; // Full daily data for details

  const ForecastTile({
    super.key,
    required this.date,
    required this.icon,
    required this.condition,
    required this.maxTemp,
    required this.minTemp,
    this.isDay = true,
    this.dailyWeather,
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
            // Header
            Row(
              children: [
                Image.network(icon,
                    width: 64,
                    height: 64,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.cloud, size: 64, color: fg)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_formatDateDisplay(d.date),
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: fg)),
                      Text(d.condition,
                          style: TextStyle(
                              fontSize: 16, color: fg.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${d.maxTemp.toStringAsFixed(0)}°",
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700])),
                    Text("${d.minTemp.toStringAsFixed(0)}°",
                        style:
                            TextStyle(fontSize: 22, color: Colors.blue[600])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Parameters Grid
            Wrap(
              spacing: 12,
              runSpacing: 12,
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

  Widget _buildDetailItem(IconData icon, String label, String value, Color fg) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: fg.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: fg)),
          Text(label,
              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.6))),
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

    return GestureDetector(
      onTap: () => _showDayDetails(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Image.network(
                  icon,
                  width: 52,
                  height: 52,
                  errorBuilder: (_, __, ___) => Icon(Icons.cloud,
                      size: 48, color: fg.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_formatDateDisplay(date),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: fg)),
                      Text(condition,
                          style: TextStyle(
                              fontSize: 13, color: fg.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("$maxTemp°C",
                        style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    Text("$minTemp°C",
                        style:
                            TextStyle(color: Colors.blue[400], fontSize: 14)),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    color: fg.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
