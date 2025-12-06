// ============================================
// 14. lib/utils/background_utils.dart
// ============================================

import 'package:flutter/material.dart';

LinearGradient dynamicGradient(String condition, bool isDay) {
  final cond = condition.toLowerCase();

  if (cond.contains('rain') ||
      cond.contains('shower') ||
      cond.contains('thunder')) {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0F2A44), Color(0xFF093B5A)],
    );
  }

  if (cond.contains('cloud') || cond.contains('overcast')) {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3A4A6B), Color(0xFF1F2A44)],
    );
  }

  if (!isDay) {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF050F24), Color(0xFF0D1B33)],
    );
  }

  return const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF87CEEB), Color(0xFFE0F7FA)],
  );
}

Color foregroundForCard(bool isDay) {
  return isDay ? Colors.black87 : Colors.white;
}

Color cardTint(bool isDay) {
  return isDay
      ? Colors.white.withValues(alpha: 0.35)
      : Colors.black.withValues(alpha: 0.32);
}
