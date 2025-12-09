// lib/widgets/sun_widget.dart - COMPACT VERSION

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
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Arc - reduced height
              SizedBox(
                height: 70,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SunArcPainter(
                    progress: progress,
                    color: fg,
                    isDay: isDay,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Sunrise and Sunset row - compact
              Row(
                children: [
                  _buildTimeInfo(
                    Icons.wb_sunny_rounded,
                    sunrise,
                    fg,
                    Colors.orange.shade400,
                  ),
                  const Spacer(),
                  _buildTimeInfo(
                    Icons.nights_stay_rounded,
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

  Widget _buildTimeInfo(
      IconData icon, String time, Color fg, Color accentColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: accentColor),
        const SizedBox(width: 6),
        Text(
          time,
          style: TextStyle(
            fontSize: 13,
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint progressArcPaint = Paint()
      ..shader = LinearGradient(
        colors: isDay
            ? [Colors.orange.shade300, Colors.amber.shade200]
            : [Colors.deepPurple.shade300, Colors.indigo.shade300],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Smaller arc
    final double arcHeight = size.height * 0.9;
    final Rect arcRect = Rect.fromLTWH(
      20,
      size.height - arcHeight / 2,
      size.width - 40,
      arcHeight,
    );

    canvas.drawArc(arcRect, pi, pi, false, arcPaint);
    canvas.drawArc(arcRect, pi, pi * progress, false, progressArcPaint);

    final double angle = pi + pi * progress;
    final double radiusX = (size.width - 40) / 2;
    final double radiusY = arcHeight / 2;
    final double centerX = size.width / 2;
    final double centerY = size.height - arcHeight / 2 + radiusY;
    final double x = centerX + radiusX * cos(angle);
    final double y = centerY + radiusY * sin(angle);

    // Sun glow - smaller
    final Paint glowPaint = Paint()
      ..shader = RadialGradient(
        colors: isDay
            ? [
                Colors.orange.shade300.withValues(alpha: 0.5),
                Colors.orange.shade200.withValues(alpha: 0.2),
                Colors.transparent,
              ]
            : [
                Colors.deepPurple.shade200.withValues(alpha: 0.4),
                Colors.deepPurple.shade100.withValues(alpha: 0.15),
                Colors.transparent,
              ],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 16));

    canvas.drawCircle(Offset(x, y), 16, glowPaint);

    // Sun circle - smaller
    final Paint sunPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDay
            ? [Colors.orange.shade400, Colors.amber.shade300]
            : [Colors.deepPurple.shade300, Colors.indigo.shade200],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 7));

    canvas.drawCircle(Offset(x, y), 7, sunPaint);

    final Paint sunBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(Offset(x, y), 7, sunBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
