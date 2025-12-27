// lib/widgets/aqi_bar_widget.dart
// Premium AQI bar for home screen - tappable to open detailed AQI screen

import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/aqi_service.dart';
import '../screens/aqi_detail_screen.dart';
import '../utils/app_theme.dart';

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
    final theme = AppTheme(isDay: isDay);

    if (isLoading) {
      return _buildLoadingBar(theme);
    }

    if (aqiData == null) {
      return const SizedBox.shrink();
    }

    final aqiColor = AqiService.getAqiColor(aqiData!.usAqi);
    final classification = AqiService.getAqiClassification(aqiData!.usAqi);

    return GestureDetector(
      onTap: () => _openAqiDetailScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDay
                    ? [Colors.white.withValues(alpha: 0.4), Colors.white.withValues(alpha: 0.25)]
                    : [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.06)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDay ? 0.5 : 0.15),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDay ? 0.08 : 0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                // AQI Circle indicator with gradient border
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        aqiColor.withValues(alpha: 0.2),
                        aqiColor.withValues(alpha: 0.05),
                      ],
                    ),
                    border: Border.all(color: aqiColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: aqiColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      aqiData!.usAqi.toString(),
                      style: TextStyle(
                        color: aqiColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // AQI Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.eco_rounded, color: aqiColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Air Quality',
                            style: theme.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: aqiColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: aqiColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              classification,
                              style: TextStyle(
                                color: aqiColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _getHealthAdvice(aqiData!.usAqi),
                              style: theme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.textTertiary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBar(AppTheme theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDay
                  ? [Colors.white.withValues(alpha: 0.4), Colors.white.withValues(alpha: 0.25)]
                  : [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.06)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDay ? 0.5 : 0.15),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.textPrimary.withValues(alpha: 0.1),
                ),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Loading Air Quality...',
                style: theme.bodyMedium,
              ),
            ],
          ),
        ),
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
