// lib/services/open_meteo_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenMeteoService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Fetch weather by coordinates
  static Future<Map<String, dynamic>?> fetchWeather(
      double lat, double lon) async {
    final url = '$_baseUrl?'
        'latitude=$lat&longitude=$lon'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_sum,precipitation_hours,precipitation_probability_max,wind_gusts_10m_max,wind_direction_10m_dominant'
        '&hourly=temperature_2m,relative_humidity_2m,dew_point_2m,precipitation,rain,showers,snowfall,weather_code,pressure_msl,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,is_day'
        '&current=temperature_2m,relative_humidity_2m,is_day,precipitation,rain,showers,snowfall,weather_code,cloud_cover,pressure_msl,wind_gusts_10m,wind_speed_10m,wind_direction_10m,dew_point_2m,apparent_temperature,uv_index'
        '&models=ecmwf_ifs'
        '&timezone=auto&forecast_days=7';
    print('OPEN-METEO REQUEST URL: $url');

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

  /// Fetch weather by city name using geocoding
  static Future<Map<String, dynamic>?> fetchWeatherByCity(String city) async {
    // First geocode the city
    final geoUrl =
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=en&format=json';

    try {
      final geoResponse = await http.get(Uri.parse(geoUrl));
      if (geoResponse.statusCode != 200) return null;

      final geoData = jsonDecode(geoResponse.body);
      final results = geoData['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final location = results[0];
      final lat = location['latitude'];
      final lon = location['longitude'];
      final cityName = location['name'] ?? city;
      final country = location['country'] ?? '';

      // Fetch weather for coordinates
      final weatherData = await fetchWeather(lat, lon);
      if (weatherData == null) return null;

      // Add city name to response for controller to use
      weatherData['_city_name'] =
          '$cityName${country.isNotEmpty ? ', $country' : ''}';

      return weatherData;
    } catch (_) {
      return null;
    }
  }

  /// Get weather description from WMO code
  static String getWeatherDescription(int code) {
    return WMOWeatherCode.getDescription(code);
  }

  /// Get weather icon URL from WMO code
  static String getWeatherIcon(int code, bool isDay) {
    final iconFile = WMOWeatherCode.getIcon(code, isDay);
    final url = 'https://cdn.weatherapi.com/weather/64x64/${isDay ? 'day' : 'night'}/$iconFile';
    print('🌤️ getWeatherIcon: code=$code, isDay=$isDay, iconFile=$iconFile, url=$url');
    return url;
  }
}

/// WMO Weather interpretation codes (WW)
/// https://open-meteo.com/en/docs#weathervariables
class WMOWeatherCode {
  static String getDescription(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
        return 'Fog';
      case 48:
        return 'Depositing rime fog';
      case 51:
        return 'Light drizzle';
      case 53:
        return 'Moderate drizzle';
      case 55:
        return 'Dense drizzle';
      case 56:
        return 'Light freezing drizzle';
      case 57:
        return 'Dense freezing drizzle';
      case 61:
        return 'Slight rain';
      case 63:
        return 'Moderate rain';
      case 65:
        return 'Heavy rain';
      case 66:
        return 'Light freezing rain';
      case 67:
        return 'Heavy freezing rain';
      case 71:
        return 'Slight snow fall';
      case 73:
        return 'Moderate snow fall';
      case 75:
        return 'Heavy snow fall';
      case 77:
        return 'Snow grains';
      case 80:
        return 'Slight rain showers';
      case 81:
        return 'Moderate rain showers';
      case 82:
        return 'Violent rain showers';
      case 85:
        return 'Slight snow showers';
      case 86:
        return 'Heavy snow showers';
      case 95:
        return 'Thunderstorm';
      case 96:
        return 'Thunderstorm with slight hail';
      case 99:
        return 'Thunderstorm with heavy hail';
      default:
        return 'Unknown';
    }
  }

  /// Get icon filename for WMO code (uses WeatherAPI CDN format)
  static String getIcon(int code, bool isDay) {
    switch (code) {
      case 0: // Clear sky - pure sun/moon
        return '113.png';
      case 1: // Mainly clear - sun/moon with some clouds
        return '116.png';
      case 2: // Partly cloudy - sun/moon with more clouds
        return '119.png';
      case 3: // Overcast - full clouds
        return '122.png';
      case 45: // Fog
      case 48: // Rime fog
        return '248.png';
      case 51: // Light drizzle
      case 53: // Moderate drizzle
      case 55: // Dense drizzle
        return '266.png';
      case 56: // Freezing drizzle
      case 57:
        return '311.png';
      case 61: // Slight rain
        return '296.png';
      case 63: // Moderate rain
        return '302.png';
      case 65: // Heavy rain
        return '308.png';
      case 66: // Freezing rain
      case 67:
        return '314.png';
      case 71: // Slight snow
        return '326.png';
      case 73: // Moderate snow
        return '332.png';
      case 75: // Heavy snow
        return '338.png';
      case 77: // Snow grains
        return '350.png';
      case 80: // Slight showers
        return '353.png';
      case 81: // Moderate showers
        return '356.png';
      case 82: // Violent showers
        return '359.png';
      case 85: // Snow showers slight
        return '368.png';
      case 86: // Snow showers heavy
        return '371.png';
      case 95: // Thunderstorm
        return '389.png';
      case 96: // Thunderstorm with hail
      case 99:
        return '395.png';
      default:
        return '116.png';
    }
  }
}
