// lib/widgets/sun_widget.dart - COMPACT HORIZONTAL LINE VERSION

import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/background_utils.dart';

class SunWidget extends StatelessWidget {
  final String sunrise;
  final String sunset;
  final bool isDay;

  const SunWidget({
    super.key,
    required this.sunrise,
    required this.sunset,
    required this.isDay,
  });

  double _toMinutes(String time) {
    try {
      final parts = time.split(" ");
      final hm = parts[0].split(":");

      int h = int.parse(hm[0]);
      int m = int.parse(hm[1]);
      bool pm = parts[1].toLowerCase() == "pm";

      if (pm && h != 12) h += 12;
      if (!pm && h == 12) h = 0;

      return (h * 60 + m).toDouble();
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(isDay);

    final double riseM = _toMinutes(sunrise);
    final double setM = _toMinutes(sunset);

    final now = TimeOfDay.now();
    final nowM = (now.hour * 60 + now.minute).toDouble();

    double progress = 0.0;

    if (setM > riseM) {
      progress = ((nowM - riseM) / (setM - riseM)).clamp(0.0, 1.0);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDay
                  ? [
                      Colors.white.withValues(alpha: 0.3),
                      Colors.white.withValues(alpha: 0.2),
                    ]
                  : [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.2),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sunrise and Sunset row with progress line
              Row(
                children: [
                  // Sunrise
                  _buildTimeColumn(
                    Icons.wb_sunny_rounded,
                    'Sunrise',
                    sunrise,
                    fg,
                    Colors.orange.shade400,
                  ),
                  const SizedBox(width: 12),
                  // Progress line
                  Expanded(
                    child: _buildProgressLine(progress, fg),
                  ),
                  const SizedBox(width: 12),
                  // Sunset
                  _buildTimeColumn(
                    Icons.nights_stay_rounded,
                    'Sunset',
                    sunset,
                    fg,
                    Colors.deepPurple.shade300,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeColumn(
      IconData icon, String label, String time, Color fg, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: accentColor),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: fg.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          time,
          style: TextStyle(
            fontSize: 12,
            color: fg,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressLine(double progress, Color fg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lineWidth = constraints.maxWidth;
        final sunPosition = lineWidth * progress;

        return SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background line
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Progress line
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: sunPosition,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDay
                          ? [Colors.orange.shade300, Colors.amber.shade400]
                          : [
                              Colors.deepPurple.shade300,
                              Colors.indigo.shade300
                            ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Sun indicator
              Positioned(
                left: sunPosition - 12,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDay
                          ? [Colors.orange.shade400, Colors.amber.shade300]
                          : [
                              Colors.deepPurple.shade300,
                              Colors.indigo.shade200
                            ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDay
                            ? Colors.orange.withValues(alpha: 0.4)
                            : Colors.deepPurple.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isDay ? Icons.wb_sunny : Icons.nightlight_round,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
