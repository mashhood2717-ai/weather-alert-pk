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
  // Street address from geocoding
  final String? streetAddress;
  final String? fullAddress;

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
    this.streetAddress,
    this.fullAddress,
  });

  /// Create a copy with updated address and optionally city name
  CurrentWeather copyWithAddress({
    String? city,
    String? streetAddress,
    String? fullAddress,
  }) {
    return CurrentWeather(
      city: city ?? this.city,
      tempC: tempC,
      condition: condition,
      icon: icon,
      humidity: humidity,
      windKph: windKph,
      windDeg: windDeg,
      feelsLikeC: feelsLikeC,
      dewpointC: dewpointC,
      pressureMb: pressureMb,
      visKm: visKm,
      gustKph: gustKph,
      isDay: isDay,
      lat: lat,
      lon: lon,
      uvIndex: uvIndex,
      cloudCover: cloudCover,
      precipitation: precipitation,
      rain: rain,
      snowfall: snowfall,
      streetAddress: streetAddress ?? this.streetAddress,
      fullAddress: fullAddress ?? this.fullAddress,
    );
  }
}
