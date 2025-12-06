// ============================================
// 15. lib/utils/wind_utils.dart
// ============================================

String windDegToCompass(int? degrees) {
  if (degrees == null) return '--';

  if (degrees >= 337.5 || degrees < 22.5) return 'N';
  if (degrees >= 22.5 && degrees < 67.5) return 'NE';
  if (degrees >= 67.5 && degrees < 112.5) return 'E';
  if (degrees >= 112.5 && degrees < 157.5) return 'SE';
  if (degrees >= 157.5 && degrees < 202.5) return 'S';
  if (degrees >= 202.5 && degrees < 247.5) return 'SW';
  if (degrees >= 247.5 && degrees < 292.5) return 'W';
  if (degrees >= 292.5 && degrees < 337.5) return 'NW';

  return '--';
}
