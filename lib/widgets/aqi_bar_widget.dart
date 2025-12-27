// lib/widgets/aqi_bar_widget.dart
// Compact AQI bar for home screen - tappable to open detailed AQI screen

import 'package:flutter/material.dart';
import '../services/aqi_service.dart';
import '../screens/aqi_detail_screen.dart';

class AqiBarWidget extends StatelessWidget {
  final AirQualityData? aqiData;
  final bool isDay;
  final bool isLoading;

  const AqiBarWidget({
    super.key,
    required this.aqiData,
    required this.isDay,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDay ? Colors.black87 : Colors.white;
    final tint = isDay
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.1);

    if (isLoading) {
      return _buildLoadingBar(fg, tint);
    }

    if (aqiData == null) {
      return const SizedBox.shrink(); // Don't show if no data
    }

    final aqiColor = AqiService.getAqiColor(aqiData!.usAqi);
    final classification = AqiService.getAqiClassification(aqiData!.usAqi);

    return GestureDetector(
      onTap: () => _openAqiDetailScreen(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: fg.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            // AQI Circle indicator
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: aqiColor.withValues(alpha: 0.2),
                border: Border.all(color: aqiColor, width: 3),
              ),
              child: Center(
                child: Text(
                  aqiData!.usAqi.toString(),
                  style: TextStyle(
                    color: aqiColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // AQI Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.air, color: aqiColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Air Quality',
                        style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: aqiColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          classification,
                          style: TextStyle(
                            color: aqiColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _getHealthAdvice(aqiData!.usAqi),
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Arrow indicator
            Icon(
              Icons.chevron_right,
              color: fg.withValues(alpha: 0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBar(Color fg, Color tint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: 0.1),
            ),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Loading Air Quality...',
            style: TextStyle(
              color: fg.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _openAqiDetailScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AqiDetailScreen(
          aqiData: aqiData!,
          isDay: isDay,
        ),
      ),
    );
  }

  String _getHealthAdvice(int aqi) {
    if (aqi <= 50) return 'Air quality is good';
    if (aqi <= 100) return 'Acceptable for most';
    if (aqi <= 150) return 'Sensitive groups caution';
    if (aqi <= 200) return 'Reduce outdoor activity';
    if (aqi <= 300) return 'Health alert';
    return 'Hazardous conditions';
  }
}
