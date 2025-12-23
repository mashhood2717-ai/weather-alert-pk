// lib/models/daily_weather.dart

class DailyWeather {
  final String date;
  final double maxTemp;
  final double minTemp;
  final String condition;
  final String icon;
  final String sunrise;
  final String sunset;
  // New Open-Meteo parameters
  final double? uvIndexMax;
  final double? precipitationSum;
  final int? precipitationProbability;
  final double? windGustsMax;
  final int? windDirectionDominant;
  
  // Day/Night specific weather data
  final String? dayIcon;
  final String? dayCondition;
  final double? dayHighTemp;
  final String? nightIcon;
  final String? nightCondition;
  final double? nightLowTemp;

  DailyWeather({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.condition,
    required this.icon,
    required this.sunrise,
    required this.sunset,
    this.uvIndexMax,
    this.precipitationSum,
    this.precipitationProbability,
    this.windGustsMax,
    this.windDirectionDominant,
    this.dayIcon,
    this.dayCondition,
    this.dayHighTemp,
    this.nightIcon,
    this.nightCondition,
    this.nightLowTemp,
  });
}
