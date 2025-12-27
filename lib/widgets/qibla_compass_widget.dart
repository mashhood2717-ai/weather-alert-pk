// lib/widgets/qibla_compass_widget.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';

/// Qibla Compass Widget - Shows direction to Kaaba
class QiblaCompassWidget extends StatefulWidget {
  final bool isDay;
  final double? latitude;
  final double? longitude;

  const QiblaCompassWidget({
    super.key,
    required this.isDay,
    this.latitude,
    this.longitude,
  });

  @override
  State<QiblaCompassWidget> createState() => _QiblaCompassWidgetState();
}

class _QiblaCompassWidgetState extends State<QiblaCompassWidget>
    with SingleTickerProviderStateMixin {
  // Kaaba coordinates
  static const double _kaabaLat = 21.4225;
  static const double _kaabaLon = 39.8262;

  double? _qiblaDirection; // Bearing from current location to Kaaba
  bool _loading = true;
  String? _error;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initCompass();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(QiblaCompassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _calculateQiblaDirection();
    }
  }

  Future<void> _initCompass() async {
    // Check location permission
    final status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      final result = await Permission.locationWhenInUse.request();
      if (!result.isGranted) {
        setState(() {
          _error = 'Location permission required for Qibla direction';
          _loading = false;
        });
        return;
      }
    }

    // Check if compass is available
    final isAvailable = await FlutterCompass.events != null;
    if (!isAvailable) {
      setState(() {
        _error = 'Compass sensor not available on this device';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = false;
    });

    _calculateQiblaDirection();
  }

  /// Calculate bearing from current location to Kaaba using Haversine formula
  void _calculateQiblaDirection() {
    if (widget.latitude == null || widget.longitude == null) {
      setState(() => _error = 'Location not available');
      return;
    }

    final lat1 = widget.latitude! * pi / 180;
    final lon1 = widget.longitude! * pi / 180;
    final lat2 = _kaabaLat * pi / 180;
    final lon2 = _kaabaLon * pi / 180;

    final dLon = lon2 - lon1;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    var bearing = atan2(y, x) * 180 / pi;
    bearing = (bearing + 360) % 360; // Normalize to 0-360

    setState(() {
      _qiblaDirection = bearing;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isDay ? Colors.black87 : Colors.white;
    final tint = widget.isDay
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.1);

    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: fg),
            const SizedBox(height: 16),
            Text('Initializing Compass...', style: TextStyle(color: fg)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_off, color: fg, size: 64),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: fg, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initCompass,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: fg.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.explore, color: fg, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Qibla Compass',
                      style: TextStyle(
                        color: fg,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Direction to Kaaba, Makkah',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Compass
          StreamBuilder<CompassEvent>(
            stream: FlutterCompass.events,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error reading compass: ${snapshot.error}',
                    style: TextStyle(color: fg),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data?.heading == null) {
                return Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: fg),
                      const SizedBox(height: 16),
                      Text(
                        'Calibrating compass...\nMove device in figure-8 pattern',
                        style: TextStyle(color: fg),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              final heading = snapshot.data!.heading!;

              // Calculate rotation: Qibla direction relative to device heading
              final qiblaRotation = _qiblaDirection != null
                  ? (_qiblaDirection! - heading) * pi / 180
                  : 0.0;

              return _buildCompass(fg, tint, heading, qiblaRotation);
            },
          ),

          const SizedBox(height: 24),

          // Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: fg.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  fg,
                  Icons.my_location,
                  'Your Location',
                  '${widget.latitude?.toStringAsFixed(4) ?? '--'}°N, ${widget.longitude?.toStringAsFixed(4) ?? '--'}°E',
                ),
                Divider(color: fg.withValues(alpha: 0.1), height: 24),
                _buildInfoRow(
                  fg,
                  Icons.mosque,
                  'Kaaba Location',
                  '21.4225°N, 39.8262°E',
                ),
                Divider(color: fg.withValues(alpha: 0.1), height: 24),
                _buildInfoRow(
                  fg,
                  Icons.navigation,
                  'Qibla Bearing',
                  _qiblaDirection != null
                      ? '${_qiblaDirection!.toStringAsFixed(1)}° ${_getCardinalDirection(_qiblaDirection!)}'
                      : '--',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Point the green arrow towards Qibla. Keep device flat and away from magnets.',
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompass(
      Color fg, Color tint, double heading, double qiblaRotation) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring (rotates with device heading)
          Transform.rotate(
            angle: -heading * pi / 180,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: fg.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: CustomPaint(
                painter: _CompassDialPainter(fg: fg),
              ),
            ),
          ),

          // Inner circle
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint,
              border: Border.all(
                color: fg.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),

          // Qibla arrow (points to Qibla)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: qiblaRotation,
                child: Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mosque,
                        color: Colors.green,
                        size: 32,
                      ),
                      Container(
                        width: 4,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.green,
                              Colors.green.withValues(alpha: 0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Center dot
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),

          // Heading display at bottom
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${heading.toStringAsFixed(0)}° ${_getCardinalDirection(heading)}',
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(Color fg, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: fg.withValues(alpha: 0.7), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getCardinalDirection(double degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((degrees + 22.5) / 45).floor() % 8;
    return directions[index];
  }
}

/// Custom painter for compass dial
class _CompassDialPainter extends CustomPainter {
  final Color fg;

  _CompassDialPainter({required this.fg});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final paint = Paint()
      ..color = fg
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw cardinal directions
    const directions = ['N', 'E', 'S', 'W'];
    const colors = [Colors.red, null, null, null]; // N is red

    for (var i = 0; i < 4; i++) {
      final angle = i * pi / 2 - pi / 2; // Start from top (N)
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);

      final textPainter = TextPainter(
        text: TextSpan(
          text: directions[i],
          style: TextStyle(
            color: colors[i] ?? fg,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    // Draw tick marks
    for (var i = 0; i < 36; i++) {
      final angle = i * pi / 18 - pi / 2;
      final isCardinal = i % 9 == 0;
      final isMajor = i % 3 == 0;

      final innerRadius = radius - (isCardinal ? 25 : (isMajor ? 15 : 8));
      final outerRadius = radius - 5;

      final x1 = center.dx + innerRadius * cos(angle);
      final y1 = center.dy + innerRadius * sin(angle);
      final x2 = center.dx + outerRadius * cos(angle);
      final y2 = center.dy + outerRadius * sin(angle);

      paint.strokeWidth = isCardinal ? 3 : (isMajor ? 2 : 1);
      paint.color = fg.withValues(alpha: isCardinal ? 1.0 : 0.5);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
