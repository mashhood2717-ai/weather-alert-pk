// lib/widgets/metar_tile.dart - PROFESSIONAL UI

import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/background_utils.dart';

class MetarTile extends StatelessWidget {
  final String station;
  final String observed;
  final String temp;
  final String wind;
  final String visibility;
  final String pressure;
  final String humidity;
  final String dewpoint;
  final String iconUrl;
  final bool isDay;

  const MetarTile({
    super.key,
    required this.station,
    required this.observed,
    required this.temp,
    required this.wind,
    required this.visibility,
    required this.pressure,
    required this.humidity,
    required this.dewpoint,
    required this.iconUrl,
    this.isDay = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(isDay);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDay
                  ? [
                      Colors.white.withValues(alpha: 0.35),
                      Colors.white.withValues(alpha: 0.25),
                    ]
                  : [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.25),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDay
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Image.network(
                      iconUrl,
                      width: 56,
                      height: 56,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.flight_rounded,
                        size: 56,
                        color: fg.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.flight_rounded,
                              size: 16,
                              color: fg.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              station,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: fg,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: fg.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Observed: $observed",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: fg.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      fg.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow(
                  Icons.thermostat_rounded, "Temperature", temp, fg),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.air_rounded, "Wind", wind, fg),
              const SizedBox(height: 12),
              _buildDetailRow(
                  Icons.visibility_rounded, "Visibility", visibility, fg),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.compress_rounded, "Pressure", pressure, fg),
              const SizedBox(height: 12),
              _buildDetailRow(
                  Icons.water_drop_rounded, "Humidity", humidity, fg),
              const SizedBox(height: 12),
              _buildDetailRow(
                  Icons.water_drop_outlined, "Dew Point", dewpoint, fg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, Color fg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fg.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: fg.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: fg.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: fg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
