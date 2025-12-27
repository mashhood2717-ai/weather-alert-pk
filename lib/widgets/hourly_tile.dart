// lib/widgets/hourly_tile.dart - Premium glass design

import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class HourlyTile extends StatelessWidget {
  final String time;
  final String temp;
  final String icon;
  final String humidity;
  final bool isDay;

  const HourlyTile({
    super.key,
    required this.time,
    required this.temp,
    required this.icon,
    required this.humidity,
    this.isDay = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme(isDay: isDay);

    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDay
              ? [
                  Colors.white.withValues(alpha: 0.4),
                  Colors.white.withValues(alpha: 0.2),
                ]
              : [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDay ? 0.5 : 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDay ? 0.05 : 0.2),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time
          Text(
            time,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          // Icon
          Image.network(
            icon,
            width: 36,
            height: 36,
            cacheWidth: 72,
            cacheHeight: 72,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => Icon(
              Icons.cloud,
              size: 32,
              color: theme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          // Temperature
          Text(
            temp,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          // Humidity
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.water_drop_rounded,
                size: 10,
                color: Colors.blue.shade300,
              ),
              const SizedBox(width: 2),
              Text(
                "$humidity%",
                style: TextStyle(
                  color: theme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
