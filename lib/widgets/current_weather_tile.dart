// lib/widgets/current_weather_tile.dart - Premium Apple-style design

import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

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
  final String? streetAddress;
  final VoidCallback? onIconTap;

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
    this.streetAddress,
    this.onIconTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme(isDay: isDay);
    final safeIcon = (icon.isEmpty || icon == "null") ? null : icon;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDay
                  ? [
                      Colors.white.withValues(alpha: 0.45),
                      Colors.white.withValues(alpha: 0.25),
                      Colors.white.withValues(alpha: 0.15),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.04),
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDay ? 0.5 : 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDay ? 0.08 : 0.25),
                blurRadius: 30,
                spreadRadius: -5,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Location row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.textPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: theme.textSecondary,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          city,
                          style: theme.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (streetAddress != null && streetAddress!.isNotEmpty)
                          Text(
                            streetAddress!,
                            style: theme.bodySmall.copyWith(
                              color: theme.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Main temperature and icon row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Temperature display
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Large temperature
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _extractTemp(temp),
                              style: TextStyle(
                                fontSize: 80,
                                fontWeight: FontWeight.w100,
                                color: theme.textPrimary,
                                height: 0.9,
                                letterSpacing: -5,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _extractUnit(temp),
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w200,
                                  color: theme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Condition
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.textPrimary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            condition,
                            style: theme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Weather icon
                  if (safeIcon != null)
                    GestureDetector(
                      onTap: onIconTap,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: isDay
                                ? [
                                    Colors.amber.withValues(alpha: 0.2),
                                    Colors.transparent,
                                  ]
                                : [
                                    Colors.indigo.withValues(alpha: 0.2),
                                    Colors.transparent,
                                  ],
                            radius: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Image.network(
                          safeIcon,
                          width: 80,
                          height: 80,
                          cacheWidth: 160,
                          cacheHeight: 160,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.wb_cloudy_rounded,
                            size: 70,
                            color: theme.textTertiary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _extractTemp(String temp) {
    return temp.replaceAll(RegExp(r'[°][CF]'), '').trim();
  }

  String _extractUnit(String temp) {
    if (temp.contains('°F')) return '°F';
    if (temp.contains('°C')) return '°C';
    return '°';
  }
}
