// lib/models/hourly_weather.dart

class HourlyWeather {
  final String time;
  final double tempC;
  final String icon;
  final int humidity;

  HourlyWeather({
    required this.time,
    required this.tempC,
    required this.icon,
    required this.humidity,
  });
}
