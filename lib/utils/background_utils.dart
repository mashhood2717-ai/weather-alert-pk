// ============================================
// lib/utils/background_utils.dart
// Unified background utilities using new theme system
// ============================================

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Get dynamic gradient based on weather condition and time
/// Now uses the new WeatherGradients system for consistent theming
LinearGradient dynamicGradient(String condition, bool isDay) {
  return WeatherGradients.getGradient(condition, isDay);
}

/// Get foreground color for cards/text based on day/night mode
Color foregroundForCard(bool isDay) {
  return isDay ? AppColors.dayTextPrimary : AppColors.nightTextPrimary;
}

/// Get card background tint color
Color cardTint(bool isDay) {
  return isDay ? AppColors.dayCardBackground : AppColors.nightCardBackground;
}

/// Get card border color
Color cardBorderColor(bool isDay) {
  return isDay ? AppColors.dayCardBorder : AppColors.nightCardBorder;
}

/// Get secondary text color
Color secondaryTextColor(bool isDay) {
  return isDay ? AppColors.dayTextSecondary : AppColors.nightTextSecondary;
}

/// Get tertiary/hint text color
Color tertiaryTextColor(bool isDay) {
  return isDay ? AppColors.dayTextTertiary : AppColors.nightTextTertiary;
}

/// Create glass card decoration with consistent styling
BoxDecoration glassCardDecoration({
  required bool isDay,
  double borderRadius = 20,
  bool elevated = false,
}) {
  return AppTheme(isDay: isDay).glassDecoration(
    borderRadius: borderRadius,
    elevated: elevated,
  );
}

/// Simple semi-transparent card decoration
BoxDecoration simpleCardDecoration({
  required bool isDay,
  double borderRadius = 16,
}) {
  return AppTheme(isDay: isDay).simpleCardDecoration(borderRadius: borderRadius);
}
