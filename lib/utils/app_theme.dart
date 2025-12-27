// lib/utils/app_theme.dart - Unified Theme System
// Professional weather app theming inspired by Apple/Google Weather

import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Weather condition categories for theming
enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  overcast,
  mist,
  fog,
  rain,
  lightRain,
  heavyRain,
  thunderstorm,
  snow,
  sleet,
  haze,
  dust,
  windy,
}

/// App-wide color palette
class AppColors {
  // Primary brand colors
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF64B5F6);
  static const Color accent = Color(0xFF00BCD4);

  // Day mode colors
  static const Color dayTextPrimary = Color(0xDE000000); // 87% opacity
  static const Color dayTextSecondary = Color(0x99000000); // 60% opacity
  static const Color dayTextTertiary = Color(0x61000000); // 38% opacity
  static const Color dayCardBackground = Color(0x40FFFFFF); // 25% white
  static const Color dayCardBorder = Color(0x33FFFFFF); // 20% white

  // Night mode colors
  static const Color nightTextPrimary = Color(0xFFFFFFFF);
  static const Color nightTextSecondary = Color(0xB3FFFFFF); // 70% opacity
  static const Color nightTextTertiary = Color(0x80FFFFFF); // 50% opacity
  static const Color nightCardBackground = Color(0x40000000); // 25% black
  static const Color nightCardBorder = Color(0x26FFFFFF); // 15% white

  // Semantic colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Weather-specific accent colors
  static const Color sunnyAccent = Color(0xFFFFB74D);
  static const Color rainAccent = Color(0xFF64B5F6);
  static const Color stormAccent = Color(0xFF7E57C2);
  static const Color snowAccent = Color(0xFFE0E0E0);
  static const Color fogAccent = Color(0xFF90A4AE);
}

/// Dynamic gradient backgrounds based on weather and time
class WeatherGradients {
  /// Get gradient based on weather condition and time of day
  static LinearGradient getGradient(String condition, bool isDay, {DateTime? currentTime}) {
    final cond = condition.toLowerCase();
    final weatherType = _parseCondition(cond);
    
    // Check for golden hour (sunrise/sunset) effect
    final hour = currentTime?.hour ?? DateTime.now().hour;
    final isGoldenHour = (hour >= 5 && hour <= 7) || (hour >= 17 && hour <= 19);
    
    if (isGoldenHour && isDay && weatherType == WeatherCondition.clear) {
      return _goldenHourGradient(hour >= 17);
    }
    
    return _getWeatherGradient(weatherType, isDay);
  }

  static WeatherCondition _parseCondition(String cond) {
    if (cond.contains('thunder') || cond.contains('storm')) {
      return WeatherCondition.thunderstorm;
    }
    if (cond.contains('heavy rain') || cond.contains('torrential')) {
      return WeatherCondition.heavyRain;
    }
    if (cond.contains('rain') || cond.contains('drizzle') || cond.contains('shower')) {
      return WeatherCondition.rain;
    }
    if (cond.contains('snow') || cond.contains('blizzard')) {
      return WeatherCondition.snow;
    }
    if (cond.contains('sleet') || cond.contains('ice')) {
      return WeatherCondition.sleet;
    }
    if (cond.contains('fog')) {
      return WeatherCondition.fog;
    }
    if (cond.contains('mist')) {
      return WeatherCondition.mist;
    }
    if (cond.contains('haze') || cond.contains('smoke')) {
      return WeatherCondition.haze;
    }
    if (cond.contains('dust') || cond.contains('sand')) {
      return WeatherCondition.dust;
    }
    if (cond.contains('overcast')) {
      return WeatherCondition.overcast;
    }
    if (cond.contains('cloud')) {
      if (cond.contains('partly') || cond.contains('partial')) {
        return WeatherCondition.partlyCloudy;
      }
      return WeatherCondition.cloudy;
    }
    if (cond.contains('wind') || cond.contains('gust')) {
      return WeatherCondition.windy;
    }
    return WeatherCondition.clear;
  }

  static LinearGradient _goldenHourGradient(bool isSunset) {
    if (isSunset) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1A237E), // Deep indigo at top
          Color(0xFFE91E63), // Pink
          Color(0xFFFF5722), // Deep orange
          Color(0xFFFFB74D), // Warm amber at horizon
        ],
        stops: [0.0, 0.35, 0.65, 1.0],
      );
    }
    // Sunrise
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF283593), // Indigo at top
        Color(0xFF5C6BC0), // Lighter indigo
        Color(0xFFFFB74D), // Amber
        Color(0xFFFFE0B2), // Light peach at horizon
      ],
      stops: [0.0, 0.3, 0.7, 1.0],
    );
  }

  static LinearGradient _getWeatherGradient(WeatherCondition condition, bool isDay) {
    switch (condition) {
      case WeatherCondition.clear:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1976D2), // Deep blue
                  Color(0xFF42A5F5), // Medium blue
                  Color(0xFF90CAF9), // Light blue
                ],
                stops: [0.0, 0.5, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0D1B2A), // Deep navy
                  Color(0xFF1B263B), // Dark blue-gray
                  Color(0xFF415A77), // Muted blue
                ],
                stops: [0.0, 0.6, 1.0],
              );

      case WeatherCondition.partlyCloudy:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF5C6BC0), // Indigo
                  Color(0xFF7986CB), // Light indigo
                  Color(0xFFB3E5FC), // Very light blue
                ],
                stops: [0.0, 0.5, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1A237E), // Deep indigo
                  Color(0xFF283593), // Indigo
                  Color(0xFF3949AB), // Lighter indigo
                ],
                stops: [0.0, 0.5, 1.0],
              );

      case WeatherCondition.cloudy:
      case WeatherCondition.overcast:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF546E7A), // Blue gray
                  Color(0xFF78909C), // Lighter blue gray
                  Color(0xFFB0BEC5), // Even lighter
                ],
                stops: [0.0, 0.5, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF263238), // Dark blue gray
                  Color(0xFF37474F), // Blue gray
                  Color(0xFF455A64), // Lighter
                ],
                stops: [0.0, 0.5, 1.0],
              );

      case WeatherCondition.rain:
      case WeatherCondition.lightRain:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF37474F), // Dark blue gray
                  Color(0xFF455A64), // Blue gray
                  Color(0xFF607D8B), // Lighter blue gray
                ],
                stops: [0.0, 0.4, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0D1B2A), // Very dark
                  Color(0xFF1B263B), // Dark blue
                  Color(0xFF2C3E50), // Dark slate
                ],
                stops: [0.0, 0.5, 1.0],
              );

      case WeatherCondition.heavyRain:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A2E), // Very dark navy
            Color(0xFF16213E), // Dark navy
            Color(0xFF1F4068), // Slightly lighter
          ],
          stops: [0.0, 0.5, 1.0],
        );

      case WeatherCondition.thunderstorm:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A2E), // Very dark
            Color(0xFF2D132C), // Dark purple
            Color(0xFF4A1942), // Purple tint
          ],
          stops: [0.0, 0.5, 1.0],
        );

      case WeatherCondition.snow:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF78909C), // Blue gray
                  Color(0xFFB0BEC5), // Light blue gray
                  Color(0xFFECEFF1), // Very light
                ],
                stops: [0.0, 0.5, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF263238), // Dark
                  Color(0xFF37474F), // Slate
                  Color(0xFF455A64), // Lighter
                ],
                stops: [0.0, 0.5, 1.0],
              );

      case WeatherCondition.fog:
      case WeatherCondition.mist:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF90A4AE), // Gray blue
                  Color(0xFFB0BEC5), // Light gray blue
                  Color(0xFFCFD8DC), // Very light
                ],
                stops: [0.0, 0.5, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF37474F), // Dark slate
                  Color(0xFF455A64), // Slate
                  Color(0xFF546E7A), // Lighter slate
                ],
                stops: [0.0, 0.5, 1.0],
              );

      case WeatherCondition.haze:
      case WeatherCondition.dust:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF8D6E63), // Brown
                  Color(0xFFA1887F), // Light brown
                  Color(0xFFBCAAA4), // Lighter
                ],
                stops: [0.0, 0.5, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF3E2723), // Dark brown
                  Color(0xFF4E342E), // Brown
                  Color(0xFF5D4037), // Lighter
                ],
                stops: [0.0, 0.5, 1.0],
              );

      case WeatherCondition.windy:
        return isDay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF5C6BC0), // Indigo
                  Color(0xFF7986CB), // Light indigo
                  Color(0xFFC5CAE9), // Very light indigo
                ],
                stops: [0.0, 0.5, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1A237E), // Deep indigo
                  Color(0xFF283593), // Indigo
                  Color(0xFF303F9F), // Lighter
                ],
                stops: [0.0, 0.5, 1.0],
              );

      case WeatherCondition.sleet:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF37474F),
            Color(0xFF455A64),
            Color(0xFF607D8B),
          ],
          stops: [0.0, 0.5, 1.0],
        );
    }
  }
}

/// Theme helper for consistent styling
class AppTheme {
  final bool isDay;

  AppTheme({required this.isDay});

  // Text colors
  Color get textPrimary => isDay ? AppColors.dayTextPrimary : AppColors.nightTextPrimary;
  Color get textSecondary => isDay ? AppColors.dayTextSecondary : AppColors.nightTextSecondary;
  Color get textTertiary => isDay ? AppColors.dayTextTertiary : AppColors.nightTextTertiary;

  // Card styling
  Color get cardBackground => isDay ? AppColors.dayCardBackground : AppColors.nightCardBackground;
  Color get cardBorder => isDay ? AppColors.dayCardBorder : AppColors.nightCardBorder;

  // Glass effect decoration
  BoxDecoration glassDecoration({
    double borderRadius = 20,
    double borderWidth = 1.5,
    bool elevated = false,
  }) {
    return BoxDecoration(
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
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: Colors.white.withValues(alpha: isDay ? 0.4 : 0.2),
        width: borderWidth,
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDay ? 0.1 : 0.3),
                blurRadius: 20,
                spreadRadius: -5,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    );
  }

  // Simple card decoration (no gradient, just solid)
  BoxDecoration simpleCardDecoration({double borderRadius = 16}) {
    return BoxDecoration(
      color: isDay
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: Colors.white.withValues(alpha: isDay ? 0.3 : 0.15),
        width: 1,
      ),
    );
  }

  // Text styles
  TextStyle get displayLarge => TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w200,
        color: textPrimary,
        letterSpacing: -3,
        height: 1.0,
      );

  TextStyle get displayMedium => TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w300,
        color: textPrimary,
        letterSpacing: -2,
      );

  TextStyle get headlineLarge => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.5,
      );

  TextStyle get headlineMedium => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  TextStyle get titleLarge => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  TextStyle get titleMedium => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  TextStyle get bodyLarge => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  TextStyle get bodyMedium => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  TextStyle get bodySmall => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textTertiary,
      );

  TextStyle get labelLarge => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textSecondary,
        letterSpacing: 0.5,
      );

  TextStyle get labelSmall => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: textTertiary,
        letterSpacing: 0.3,
      );
}

/// Animated gradient background widget
class AnimatedWeatherBackground extends StatefulWidget {
  final String condition;
  final bool isDay;
  final Widget child;
  final Duration animationDuration;

  const AnimatedWeatherBackground({
    super.key,
    required this.condition,
    required this.isDay,
    required this.child,
    this.animationDuration = const Duration(milliseconds: 800),
  });

  @override
  State<AnimatedWeatherBackground> createState() => _AnimatedWeatherBackgroundState();
}

class _AnimatedWeatherBackgroundState extends State<AnimatedWeatherBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  LinearGradient? _previousGradient;
  LinearGradient? _currentGradient;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _currentGradient = WeatherGradients.getGradient(widget.condition, widget.isDay);
  }

  @override
  void didUpdateWidget(AnimatedWeatherBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition != widget.condition || oldWidget.isDay != widget.isDay) {
      _previousGradient = _currentGradient;
      _currentGradient = WeatherGradients.getGradient(widget.condition, widget.isDay);
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final gradient = _previousGradient != null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: List.generate(
                  _currentGradient!.colors.length,
                  (i) => Color.lerp(
                    _previousGradient!.colors[i.clamp(0, _previousGradient!.colors.length - 1)],
                    _currentGradient!.colors[i],
                    _animation.value,
                  )!,
                ),
              )
            : _currentGradient!;

        return Container(
          decoration: BoxDecoration(gradient: gradient),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Floating particles effect for weather ambiance
class WeatherParticles extends StatefulWidget {
  final String condition;
  final bool isDay;

  const WeatherParticles({
    super.key,
    required this.condition,
    required this.isDay,
  });

  @override
  State<WeatherParticles> createState() => _WeatherParticlesState();
}

class _WeatherParticlesState extends State<WeatherParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
    _generateParticles();
  }

  void _generateParticles() {
    _particles.clear();
    final cond = widget.condition.toLowerCase();
    
    int count = 0;
    if (cond.contains('rain')) {
      count = 30;
    } else if (cond.contains('snow')) {
      count = 25;
    } else if (cond.contains('clear') && !widget.isDay) {
      count = 15; // Stars at night
    }
    
    for (int i = 0; i < count; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 3 + 1,
        speed: _random.nextDouble() * 0.5 + 0.3,
        opacity: _random.nextDouble() * 0.5 + 0.3,
      ));
    }
  }

  @override
  void didUpdateWidget(WeatherParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition != widget.condition) {
      _generateParticles();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_particles.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            progress: _controller.value,
            condition: widget.condition,
            isDay: widget.isDay,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Particle {
  double x;
  double y;
  final double size;
  final double speed;
  final double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final String condition;
  final bool isDay;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.condition,
    required this.isDay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cond = condition.toLowerCase();
    
    Color particleColor;
    if (cond.contains('rain')) {
      particleColor = Colors.lightBlue.shade200;
    } else if (cond.contains('snow')) {
      particleColor = Colors.white;
    } else {
      particleColor = Colors.white; // Stars
    }

    for (final particle in particles) {
      final y = (particle.y + progress * particle.speed) % 1.0;
      final paint = Paint()
        ..color = particleColor.withValues(alpha: particle.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x * size.width, y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => true;
}
