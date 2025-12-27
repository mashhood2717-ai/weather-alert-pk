// lib/widgets/sun_widget.dart - Premium arc sun tracker

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

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
    final theme = AppTheme(isDay: isDay);
    final double riseM = _toMinutes(sunrise);
    final double setM = _toMinutes(sunset);
    final now = TimeOfDay.now();
    final nowM = (now.hour * 60 + now.minute).toDouble();

    double progress = 0.0;
    if (setM > riseM) {
      progress = ((nowM - riseM) / (setM - riseM)).clamp(0.0, 1.0);
    }

    // Calculate daylight hours
    final daylightMinutes = setM - riseM;
    final daylightHours = (daylightMinutes / 60).floor();
    final daylightMins = (daylightMinutes % 60).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDay
                  ? [
                      Colors.white.withValues(alpha: 0.4),
                      Colors.white.withValues(alpha: 0.2),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.15),
                      Colors.white.withValues(alpha: 0.05),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDay ? 0.5 : 0.2),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sun arc visualization
              SizedBox(
                height: 80,
                child: CustomPaint(
                  painter: _SunArcPainter(
                    progress: progress,
                    isDay: isDay,
                  ),
                  size: const Size(double.infinity, 80),
                ),
              ),
              const SizedBox(height: 16),
              // Sunrise and Sunset times
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTimeInfo(
                    icon: Icons.wb_twilight_rounded,
                    label: 'Sunrise',
                    time: sunrise,
                    color: Colors.orange.shade400,
                    theme: theme,
                  ),
                  // Daylight duration
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.textPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timelapse_rounded,
                          size: 14,
                          color: theme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${daylightHours}h ${daylightMins}m',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildTimeInfo(
                    icon: Icons.nights_stay_rounded,
                    label: 'Sunset',
                    time: sunset,
                    color: Colors.deepPurple.shade300,
                    theme: theme,
                    alignRight: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeInfo({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
    required AppTheme theme,
    bool alignRight = false,
  }) {
    return Column(
      crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!alignRight) ...[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: theme.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
            if (alignRight) ...[
              const SizedBox(width: 6),
              Icon(icon, size: 18, color: color),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _SunArcPainter extends CustomPainter {
  final double progress;
  final bool isDay;

  _SunArcPainter({required this.progress, required this.isDay});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width * 0.42;

    // Draw background arc (dashed)
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: isDay ? 0.3 : 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    // Draw progress arc
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: isDay
            ? [Colors.orange.shade300, Colors.amber.shade400, Colors.orange.shade500]
            : [Colors.deepPurple.shade300, Colors.indigo.shade300],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi * progress,
      false,
      progressPaint,
    );

    // Draw sun indicator
    final angle = math.pi + math.pi * progress;
    final sunX = center.dx + radius * math.cos(angle);
    final sunY = center.dy + radius * math.sin(angle);

    // Glow effect
    final glowPaint = Paint()
      ..color = (isDay ? Colors.orange : Colors.deepPurple).withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(sunX, sunY), 14, glowPaint);

    // Sun circle
    final sunGradient = RadialGradient(
      colors: isDay
          ? [Colors.amber.shade300, Colors.orange.shade500]
          : [Colors.indigo.shade300, Colors.deepPurple.shade400],
    );
    final sunPaint = Paint()
      ..shader = sunGradient.createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: 12));
    canvas.drawCircle(Offset(sunX, sunY), 12, sunPaint);

    // Sun border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(sunX, sunY), 12, borderPaint);

    // Horizon line
    final horizonPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - radius - 10, center.dy),
      Offset(center.dx + radius + 10, center.dy),
      horizonPaint,
    );
  }

  @override
  bool shouldRepaint(_SunArcPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDay != isDay;
}
