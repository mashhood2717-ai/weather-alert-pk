// lib/widgets/hourly_tile.dart

import 'dart:ui';
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          width: 100,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(time,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 6),
              Image.network(icon,
                  width: 42,
                  height: 42,
                  errorBuilder: (_, __, ___) => Icon(Icons.cloud,
                      size: 42, color: fg.withValues(alpha: 0.5))),
              const SizedBox(height: 6),
              Text(temp,
                  style: TextStyle(
                      color: fg, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text("$humidity%",
                  style: TextStyle(
                      color: fg.withValues(alpha: 0.75), fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
