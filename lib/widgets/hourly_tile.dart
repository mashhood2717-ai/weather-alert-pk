// lib/widgets/hourly_tile.dart - COMPACT VERSION

import 'package:flutter/material.dart';
import '../utils/background_utils.dart';

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
    final fg = foregroundForCard(isDay);
    final tint = cardTint(isDay);

    // PERFORMANCE: Removed BackdropFilter - too expensive for 24+ tiles
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Image.network(
              icon,
              width: 32,
              height: 32,
              errorBuilder: (_, __, ___) => Icon(
                Icons.cloud,
                size: 28,
                color: fg.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              temp,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.water_drop,
                  size: 10,
                  color: Colors.blue.shade300,
                ),
                const SizedBox(width: 2),
                Text(
                  "$humidity%",
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
