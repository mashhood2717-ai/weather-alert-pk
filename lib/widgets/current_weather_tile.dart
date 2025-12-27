// lib/widgets/current_weather_tile.dart - COMPACT VERSION

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
    final fg = foregroundForCard(isDay);
    final safeIcon = (icon.isEmpty || icon == "null") ? null : icon;
    final bool showIcon = safeIcon != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isDay
                    ? Colors.black.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Left side - Temperature and condition
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // City name
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          color: fg.withValues(alpha: 0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            city,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: fg,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Street address
                    if (streetAddress != null && streetAddress!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, top: 2),
                        child: Text(
                          streetAddress!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: fg.withValues(alpha: 0.6),
                            letterSpacing: 0.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Temperature
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          temp.replaceAll(RegExp(r'[°][CF]'), ''),
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w200,
                            color: fg,
                            height: 1,
                            letterSpacing: -2,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            temp.contains('°F') ? '°F' : '°C',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w300,
                              color: fg.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Condition
                    Text(
                      condition,
                      style: TextStyle(
                        fontSize: 14,
                        color: fg.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Right side - Icon
              if (showIcon)
                GestureDetector(
                  onTap: onIconTap,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDay
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Image.network(
                      safeIcon,
                      width: 60,
                      height: 60,
                      cacheWidth: 120,
                      cacheHeight: 120,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.wb_cloudy_rounded,
                        size: 50,
                        color: fg.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
