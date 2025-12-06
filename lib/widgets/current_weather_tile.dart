// lib/widgets/current_weather_tile.dart - PROFESSIONAL UI (COMPACT VERSION)

import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/background_utils.dart';

class CurrentWeatherTile extends StatelessWidget {
  final String city;
  final String temp;
  final String condition;
  final String icon;
  final bool isDay;
  final String humidity;
  final String dew;
  final String wind;
  final String pressure;
  final String windDir;

  const CurrentWeatherTile({
    super.key,
    required this.city,
    required this.temp,
    required this.condition,
    required this.icon,
    required this.humidity,
    required this.dew,
    required this.wind,
    required this.pressure,
    required this.windDir,
    this.isDay = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(isDay);
    final safeIcon = (icon.isEmpty || icon == "null") ? null : icon;
    final bool showIcon = safeIcon != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(24),
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
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isDay
                    ? Colors.black.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // CITY NAME
              Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    color: fg.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      city,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: fg,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // TEMPERATURE & ICON ROW
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Temperature
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              temp.replaceAll('°C', ''),
                              style: TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.w200,
                                color: fg,
                                height: 1,
                                letterSpacing: -3,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '°C',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w300,
                                  color: fg.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Weather Icon
                  if (showIcon)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDay
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Image.network(
                        safeIcon,
                        width: 80,
                        height: 80,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.wb_cloudy_rounded,
                          size: 70,
                          color: fg.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // CONDITION TEXT
              Text(
                condition,
                style: TextStyle(
                  fontSize: 18,
                  color: fg.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
