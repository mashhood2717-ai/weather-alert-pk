import 'dart:math';
import 'package:flutter/material.dart';
import '../services/aqi_service.dart';
import '../utils/background_utils.dart';

/// Main AQI display widget with colored ring and 7-day forecast
class AqiWidget extends StatelessWidget {
  final AirQualityData? aqiData;
  final bool isDay;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRefresh;

  const AqiWidget({
    super.key,
    required this.aqiData,
    required this.isDay,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundForCard(isDay);
    final tint = cardTint(isDay);

    if (isLoading) {
      return _buildLoadingState(fg, tint);
    }

    if (errorMessage != null || aqiData == null) {
      return _buildErrorState(fg, tint);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Main AQI Card with Ring
          _buildMainAqiCard(fg, tint),
          const SizedBox(height: 16),
          // 7-Day Forecast
          _buildForecastCard(fg, tint),
        ],
      ),
    );
  }

  Widget _buildLoadingState(Color fg, Color tint) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: fg),
          const SizedBox(height: 16),
          Text(
            'Loading Air Quality Data...',
            style: TextStyle(color: fg, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Color fg, Color tint) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: fg, size: 64),
          const SizedBox(height: 16),
          Text(
            errorMessage ?? 'Unable to load AQI data',
            style: TextStyle(color: fg, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (onRefresh != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainAqiCard(Color fg, Color tint) {
    final data = aqiData!;
    final aqiColor = AqiService.getAqiColor(data.usAqi);
    final classification = AqiService.getAqiClassification(data.usAqi);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            'Air Quality Index',
            style: TextStyle(
              color: fg,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          // AQI Ring
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: AqiRingPainter(
                aqi: data.usAqi,
                color: aqiColor,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.usAqi.toString(),
                      style: TextStyle(
                        color: aqiColor,
                        fontSize: 56,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: aqiColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: aqiColor, width: 2),
            ),
            child: Text(
              classification,
              style: TextStyle(
                color: aqiColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // PM Readings Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPmCard('PM2.5', data.pm25, 'μg/m³', fg, tint),
              _buildPmCard('PM10', data.pm10, 'μg/m³', fg, tint),
            ],
          ),
          const SizedBox(height: 16),
          // Last updated
          Text(
            'Updated: ${_formatTime(data.timestamp)}',
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
      width: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.2),
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
          const SizedBox(height: 8),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              color: fg,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              color: fg.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(Color fg, Color tint) {
    final data = aqiData!;
    if (data.forecast.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '5-Day AQI Forecast',
            style: TextStyle(
              color: fg,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ...data.forecast.map((f) => _buildForecastRow(f, fg, tint)),
        ],
      ),
    );
  }

  Widget _buildForecastRow(AqiForecast forecast, Color fg, Color tint) {
    final aqiColor = AqiService.getAqiColor(forecast.avgAqi);
    final dayName = _getDayName(forecast.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Day name
          SizedBox(
            width: 80,
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
            width: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: aqiColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              forecast.avgAqi.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: aqiColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // PM values
          SizedBox(
            width: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PM2.5: ${forecast.avgPm25.toInt()}',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
                Text(
                  'PM10: ${forecast.avgPm10.toInt()}',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
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
}

/// Custom painter for the AQI ring
class AqiRingPainter extends CustomPainter {
  final int aqi;
  final Color color;

  AqiRingPainter({required this.aqi, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 15;

    // Background ring
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring (based on AQI 0-500 scale)
    final progress = (aqi / 500).clamp(0.0, 1.0);
    final sweepAngle = 2 * pi * progress;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // Start from top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(AqiRingPainter oldDelegate) {
    return oldDelegate.aqi != aqi || oldDelegate.color != color;
  }
}
