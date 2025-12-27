// lib/utils/feels_like_utils.dart
// Utility functions for calculating Wind Chill and Heat Index

import 'dart:math';

/// Calculate the "feels like" temperature based on actual temperature, humidity, and wind speed.
/// 
/// Rules:
/// - If temp <= 15°C: Calculate Wind Chill (if wind > 0)
/// - If temp >= 25°C: Calculate Heat Index (humidity factor)
/// - If temp is between 15-25°C: Return actual temperature
/// 
/// Returns temperature in Celsius.
double calculateFeelsLike({
  required double tempC,
  required double humidity,
  required double windKph,
}) {
  if (tempC <= 15) {
    // Calculate Wind Chill
    return _calculateWindChill(tempC, windKph);
  } else if (tempC >= 25) {
    // Calculate Heat Index
    return _calculateHeatIndex(tempC, humidity);
  } else {
    // Between 15-25°C, return actual temperature
    return tempC;
  }
}

/// Wind Chill calculation using the North American/UK formula
/// Valid for temperatures at or below 10°C (50°F) and wind speeds above 4.8 km/h
/// 
/// Formula (Celsius):
/// WC = 13.12 + 0.6215*T - 11.37*V^0.16 + 0.3965*T*V^0.16
/// 
/// Where:
/// - T = Air temperature in Celsius
/// - V = Wind speed in km/h
double _calculateWindChill(double tempC, double windKph) {
  // Wind chill only applies when wind speed is above 4.8 km/h
  if (windKph < 4.8) {
    return tempC;
  }
  
  // Wind chill formula
  final v016 = pow(windKph, 0.16);
  final windChill = 13.12 + 
      (0.6215 * tempC) - 
      (11.37 * v016) + 
      (0.3965 * tempC * v016);
  
  // Wind chill should not be higher than actual temperature
  return min(windChill, tempC);
}

/// Heat Index calculation using the Rothfusz regression equation
/// Valid for temperatures at or above 27°C (80°F) and relative humidity above 40%
/// 
/// Uses simplified formula for lower temperatures/humidity, then applies
/// the full Rothfusz equation for higher values.
double _calculateHeatIndex(double tempC, double humidity) {
  // Convert to Fahrenheit for calculation (standard formula uses °F)
  final tempF = (tempC * 9 / 5) + 32;
  final rh = humidity;
  
  // Simple formula for lower values
  double heatIndexF = 0.5 * (tempF + 61.0 + ((tempF - 68.0) * 1.2) + (rh * 0.094));
  
  // If simple formula gives > 80°F, use full Rothfusz regression
  if (heatIndexF >= 80) {
    heatIndexF = -42.379 +
        2.04901523 * tempF +
        10.14333127 * rh -
        0.22475541 * tempF * rh -
        0.00683783 * tempF * tempF -
        0.05481717 * rh * rh +
        0.00122874 * tempF * tempF * rh +
        0.00085282 * tempF * rh * rh -
        0.00000199 * tempF * tempF * rh * rh;
    
    // Adjustment for low humidity
    if (rh < 13 && tempF >= 80 && tempF <= 112) {
      heatIndexF -= ((13 - rh) / 4) * sqrt((17 - (tempF - 95).abs()) / 17);
    }
    
    // Adjustment for high humidity
    if (rh > 85 && tempF >= 80 && tempF <= 87) {
      heatIndexF += ((rh - 85) / 10) * ((87 - tempF) / 5);
    }
  }
  
  // Convert back to Celsius
  final heatIndexC = (heatIndexF - 32) * 5 / 9;
  
  // Heat index should not be lower than actual temperature
  return max(heatIndexC, tempC);
}

/// Get a descriptive label for the feels like calculation
/// Returns 'Wind Chill', 'Heat Index', or null if showing actual temp
String? getFeelsLikeType(double tempC) {
  if (tempC <= 15) {
    return 'Wind Chill';
  } else if (tempC >= 25) {
    return 'Heat Index';
  }
  return null;
}
