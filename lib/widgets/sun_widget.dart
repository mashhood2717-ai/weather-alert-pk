// lib/widgets/sun_widget.dart - PROFESSIONAL UI

import 'dart:math';
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
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
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
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wb_twilight_rounded,
                    size: 20,
                    color: fg.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Sunrise & Sunset",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: fg,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 140,
                child: CustomPaint(
                  painter: _SunArcPainter(
                    progress: progress,
                    color: fg,
                    isDay: isDay,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTimeCard(
                    Icons.wb_sunny_rounded,
                    "Sunrise",
                    sunrise,
                    fg,
                    Colors.orange.shade400,
                  ),
                  _buildTimeCard(
                    Icons.nights_stay_rounded,
                    "Sunset",
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

  Widget _buildTimeCard(
      IconData icon, String label, String time, Color fg, Color accentColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: fg.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24,
              color: accentColor,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: fg.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 14,
                color: fg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SunArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isDay;

  _SunArcPainter({
    required this.progress,
    required this.color,
    required this.isDay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint arcPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint progressArcPaint = Paint()
      ..shader = LinearGradient(
        colors: isDay
            ? [Colors.orange.shade300, Colors.amber.shade200]
            : [Colors.deepPurple.shade300, Colors.indigo.shade300],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Rect arcRect =
        Rect.fromLTWH(0, size.height / 2, size.width, size.height);

    canvas.drawArc(arcRect, pi, pi, false, arcPaint);
    canvas.drawArc(arcRect, pi, pi * progress, false, progressArcPaint);

    final double angle = pi + pi * progress;
    final double radius = size.width / 2;
    final double x = size.width / 2 + radius * cos(angle);
    final double y = size.height / 2 + radius * sin(angle);

    final Paint glowPaint = Paint()
      ..shader = RadialGradient(
        colors: isDay
            ? [
                Colors.orange.shade300.withValues(alpha: 0.6),
                Colors.orange.shade200.withValues(alpha: 0.3),
                Colors.transparent,
              ]
            : [
                Colors.deepPurple.shade200.withValues(alpha: 0.5),
                Colors.deepPurple.shade100.withValues(alpha: 0.2),
                Colors.transparent,
              ],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 24));

    canvas.drawCircle(Offset(x, y), 24, glowPaint);

    final Paint sunPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDay
            ? [Colors.orange.shade400, Colors.amber.shade300]
            : [Colors.deepPurple.shade300, Colors.indigo.shade200],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 10));

    canvas.drawCircle(Offset(x, y), 10, sunPaint);

    final Paint sunBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset(x, y), 10, sunBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
