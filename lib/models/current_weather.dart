// lib/models/current_weather.dart

class CurrentWeather {
  final String city;
  final double tempC;
  final String condition;
  final String icon;
  final int humidity;
  final double windKph;
  final int? windDeg;
  final double? feelsLikeC;
  final double? dewpointC;
  final double? pressureMb;
  final double? visKm;
  final double? gustKph;
  final int isDay;
  final double lat;
  final double lon;
  // New Open-Meteo parameters
  final double? uvIndex;
  final int? cloudCover;
  final double? precipitation;
  final double? rain;
  final double? snowfall;

  CurrentWeather({
    required this.city,
    required this.tempC,
    required this.condition,
    required this.icon,
    required this.humidity,
    required this.windKph,
    this.windDeg,
    this.feelsLikeC,
    this.dewpointC,
    this.pressureMb,
    this.visKm,
    this.gustKph,
    this.isDay = 1,
    required this.lat,
    required this.lon,
    this.uvIndex,
    this.cloudCover,
    this.precipitation,
    this.rain,
    this.snowfall,
  });
}
