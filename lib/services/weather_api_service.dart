// lib/services/weather_api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../secrets.dart';

class WeatherApiService {
  static Future<Map<String, dynamic>?> fetchWeather(
      double lat, double lon) async {
    final url =
        "https://api.weatherapi.com/v1/forecast.json?key=$weatherApiKey&q=$lat,$lon&days=3&aqi=no&alerts=no";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchWeatherByCity(String city) async {
    final url =
        "https://api.weatherapi.com/v1/forecast.json?key=$weatherApiKey&q=${Uri.encodeComponent(city)}&days=3&aqi=no&alerts=no";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
