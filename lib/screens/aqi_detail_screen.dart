// lib/screens/aqi_detail_screen.dart
// Detailed AQI screen with full information and forecast

import 'dart:math';
import 'package:flutter/material.dart';
import '../services/aqi_service.dart';
import '../utils/background_utils.dart';

class AqiDetailScreen extends StatelessWidget {
  final AirQualityData aqiData;
  final bool isDay;

  const AqiDetailScreen({
    super.key,
    required this.aqiData,
    required this.isDay,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(isDay);
    final tint = cardTint(isDay);
    final aqiColor = AqiService.getAqiColor(aqiData.usAqi);
    final classification = AqiService.getAqiClassification(aqiData.usAqi);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: fg),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Air Quality',
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDay
                ? [const Color(0xFF87CEEB), const Color(0xFFE0F7FA)]
                : [const Color(0xFF050F24), const Color(0xFF0D1B33)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Main AQI Card with Ring
                _buildMainAqiCard(fg, tint, aqiColor, classification),
                const SizedBox(height: 16),
                // Health Recommendations
                _buildHealthCard(fg, tint, aqiColor),
                const SizedBox(height: 16),
                // Pollutant Details
                _buildPollutantsCard(fg, tint),
                const SizedBox(height: 16),
                // 5-Day Forecast
                if (aqiData.forecast.isNotEmpty)
                  _buildForecastCard(fg, tint),
                const SizedBox(height: 16),
                // AQI Scale Legend
                _buildAqiScaleLegend(fg, tint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainAqiCard(
      Color fg, Color tint, Color aqiColor, String classification) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // AQI Ring
          SizedBox(
            width: 180,
            height: 180,
            child: CustomPaint(
              painter: _AqiRingPainter(
                aqi: aqiData.usAqi,
                color: aqiColor,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      aqiData.usAqi.toString(),
                      style: TextStyle(
                        color: aqiColor,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'US AQI',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Classification badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: aqiColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: aqiColor, width: 2),
            ),
            child: Text(
              classification,
              style: TextStyle(
                color: aqiColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // PM Readings Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPmCard('PM2.5', aqiData.pm25, 'μg/m³', fg, tint),
              _buildPmCard('PM10', aqiData.pm10, 'μg/m³', fg, tint),
            ],
          ),
          const SizedBox(height: 16),
          // Last updated
          Text(
            'Updated: ${_formatTime(aqiData.timestamp)}',
            style: TextStyle(
              color: fg.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPmCard(
      String label, double value, String unit, Color fg, Color tint) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              color: fg,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              color: fg.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard(Color fg, Color tint, Color aqiColor) {
    final healthAdvice = _getHealthAdvice(aqiData.usAqi);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety, color: aqiColor, size: 24),
              const SizedBox(width: 10),
              Text(
                'Health Recommendations',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...healthAdvice.map((advice) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      advice['icon'] as IconData,
                      color: fg.withValues(alpha: 0.7),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        advice['text'] as String,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPollutantsCard(Color fg, Color tint) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science, color: fg.withValues(alpha: 0.8), size: 24),
              const SizedBox(width: 10),
              Text(
                'Pollutant Levels',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPollutantRow(
              'PM2.5', aqiData.pm25, 35, 'Fine particles', fg, tint),
          _buildPollutantRow(
              'PM10', aqiData.pm10, 150, 'Coarse particles', fg, tint),
        ],
      ),
    );
  }

  Widget _buildPollutantRow(String name, double value, double threshold,
      String description, Color fg, Color tint) {
    final progress = (value / threshold).clamp(0.0, 1.0);
    final color = _getPollutantColor(value, threshold);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Text(
                '${value.toStringAsFixed(1)} μg/m³',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: fg.withValues(alpha: 0.1),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(Color fg, Color tint) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today,
                  color: fg.withValues(alpha: 0.8), size: 22),
              const SizedBox(width: 10),
              Text(
                '5-Day Forecast',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...aqiData.forecast.map((f) => _buildForecastRow(f, fg, tint)),
        ],
      ),
    );
  }

  Widget _buildForecastRow(AqiForecast forecast, Color fg, Color tint) {
    final aqiColor = AqiService.getAqiColor(forecast.avgAqi);
    final dayName = _getDayName(forecast.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Day name
          SizedBox(
            width: 70,
            child: Text(
              dayName,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // AQI bar
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: fg.withValues(alpha: 0.1),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (forecast.avgAqi / 500).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: aqiColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // AQI value
          Container(
            width: 45,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: aqiColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              forecast.avgAqi.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: aqiColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAqiScaleLegend(Color fg, Color tint) {
    final scales = [
      {'label': 'Good', 'range': '0-50', 'color': const Color(0xFF4CAF50)},
      {
        'label': 'Moderate',
        'range': '51-100',
        'color': const Color(0xFFFFEB3B)
      },
      {
        'label': 'Unhealthy (Sensitive)',
        'range': '101-150',
        'color': const Color(0xFFFF9800)
      },
      {
        'label': 'Unhealthy',
        'range': '151-200',
        'color': const Color(0xFFf44336)
      },
      {
        'label': 'Very Unhealthy',
        'range': '201-300',
        'color': const Color(0xFF9C27B0)
      },
      {
        'label': 'Hazardous',
        'range': '301-500',
        'color': const Color(0xFF7B1FA2)
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  color: fg.withValues(alpha: 0.8), size: 22),
              const SizedBox(width: 10),
              Text(
                'AQI Scale',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...scales.map((scale) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: scale['color'] as Color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      scale['range'] as String,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      scale['label'] as String,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final amPm = time.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${time.minute.toString().padLeft(2, '0')} $amPm';
  }

  String _getDayName(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    final diff = dateDay.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';

    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  Color _getPollutantColor(double value, double threshold) {
    final ratio = value / threshold;
    if (ratio <= 0.5) return const Color(0xFF4CAF50); // Good
    if (ratio <= 1.0) return const Color(0xFFFF9800); // Moderate
    if (ratio <= 1.5) return const Color(0xFFf44336); // Unhealthy
    return const Color(0xFF9C27B0); // Very unhealthy
  }

  List<Map<String, dynamic>> _getHealthAdvice(int aqi) {
    if (aqi <= 50) {
      return [
        {'icon': Icons.check_circle, 'text': 'Air quality is satisfactory'},
        {
          'icon': Icons.directions_walk,
          'text': 'Great day for outdoor activities'
        },
        {'icon': Icons.window, 'text': 'Good time to open windows'},
      ];
    } else if (aqi <= 100) {
      return [
        {'icon': Icons.info, 'text': 'Air quality is acceptable'},
        {
          'icon': Icons.elderly,
          'text':
              'Sensitive individuals may experience minor effects'
        },
        {
          'icon': Icons.directions_walk,
          'text': 'Most people can enjoy outdoor activities'
        },
      ];
    } else if (aqi <= 150) {
      return [
        {
          'icon': Icons.warning_amber,
          'text': 'Unhealthy for sensitive groups'
        },
        {
          'icon': Icons.elderly,
          'text':
              'Children, elderly, and those with respiratory issues should reduce outdoor exertion'
        },
        {
          'icon': Icons.masks,
          'text': 'Consider wearing a mask outdoors'
        },
      ];
    } else if (aqi <= 200) {
      return [
        {'icon': Icons.warning, 'text': 'Unhealthy for everyone'},
        {
          'icon': Icons.home,
          'text': 'Reduce prolonged outdoor exertion'
        },
        {'icon': Icons.masks, 'text': 'Wear N95 mask if going outside'},
        {
          'icon': Icons.air,
          'text': 'Use air purifiers indoors'
        },
      ];
    } else if (aqi <= 300) {
      return [
        {'icon': Icons.dangerous, 'text': 'Very unhealthy - health alert'},
        {
          'icon': Icons.home,
          'text': 'Avoid outdoor activities'
        },
        {'icon': Icons.masks, 'text': 'Wear N95/KN95 mask outdoors'},
        {
          'icon': Icons.air,
          'text': 'Run air purifiers at maximum'
        },
        {'icon': Icons.window, 'text': 'Keep windows closed'},
      ];
    } else {
      return [
        {'icon': Icons.error, 'text': 'HAZARDOUS - Emergency conditions'},
        {'icon': Icons.home, 'text': 'Stay indoors'},
        {'icon': Icons.masks, 'text': 'Wear N95 mask even indoors if needed'},
        {
          'icon': Icons.air,
          'text': 'Seal windows and run air purifiers'
        },
        {
          'icon': Icons.local_hospital,
          'text': 'Seek medical attention if experiencing symptoms'
        },
      ];
    }
  }
}

/// Custom painter for the AQI ring
class _AqiRingPainter extends CustomPainter {
  final int aqi;
  final Color color;

  _AqiRingPainter({required this.aqi, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    // Background ring
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring
    final progress = (aqi / 500).clamp(0.0, 1.0);
    final sweepAngle = 2 * pi * progress;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_AqiRingPainter oldDelegate) {
    return oldDelegate.aqi != aqi || oldDelegate.color != color;
  }
}
