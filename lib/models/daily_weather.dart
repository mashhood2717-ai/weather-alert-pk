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
  });
}
