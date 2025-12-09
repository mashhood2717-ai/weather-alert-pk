// lib/services/weather_controller.dart
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../services/metar_service.dart';
import '../services/open_meteo_service.dart';
import '../utils/icon_mapper.dart';
import '../models/current_weather.dart';
import '../models/hourly_weather.dart';
import '../models/daily_weather.dart';
import 'location_service.dart';

class WeatherController {
  ValueNotifier<CurrentWeather?> current = ValueNotifier<CurrentWeather?>(null);
  List<HourlyWeather> hourly = [];
  List<DailyWeather> daily = [];
  Map<String, dynamic>? rawWeatherJson;

  Map<String, dynamic>? metar;
  bool metarApplied = false;
  String? lastCitySearched;

  // Callback for when data is fully loaded (for Windy update)
  VoidCallback? onDataLoaded;

  // Add local cache support
  Future<void> loadCachedWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_weather_json');
    if (cached != null) {
      try {
        final json = jsonDecode(cached);
        // Ensure _city_name is set
        if (json['_city_name'] == null) {
          // Use lastCitySearched if available
          if (lastCitySearched != null && lastCitySearched!.isNotEmpty) {
            json['_city_name'] = lastCitySearched;
          } else if (json['latitude'] != null && json['longitude'] != null) {
            json['_city_name'] =
                'Lat: ${json['latitude']}, Lon: ${json['longitude']}';
          } else {
            json['_city_name'] = 'Unknown Location';
          }
        }
        rawWeatherJson = json;
        _parseCurrentWeather(json);
        _parseForecastsOnly(json);
      } catch (_) {}
    }
  }

  Future<void> saveWeatherToCache(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('cached_weather_json', jsonEncode(json));
  }

  double _toD(v) {
    if (v == null) return 0.0;
    if (v == '--') return 0.0;
    if (v is num) return v.toDouble();
    try {
      return double.parse(v.toString());
    } catch (_) {
      return 0.0;
    }
  }

  int _toI(v) {
    if (v == null) return 0;
    if (v == '--') return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    try {
      return int.parse(v.toString());
    } catch (_) {
      return 0;
    }
  }

  // Pakistan airports with coordinates (lat, lon, ICAO)
  static const List<Map<String, dynamic>> _airports = [
    {"icao": "OPIS", "lat": 33.6167, "lon": 73.0992, "name": "Islamabad"},
    {"icao": "OPLA", "lat": 31.5216, "lon": 74.4036, "name": "Lahore"},
    {"icao": "OPFA", "lat": 31.3650, "lon": 72.9950, "name": "Faisalabad"},
    {"icao": "OPKC", "lat": 24.9065, "lon": 67.1608, "name": "Karachi"},
    {"icao": "OPST", "lat": 32.5356, "lon": 74.3639, "name": "Sialkot"},
    {"icao": "OPMT", "lat": 30.2032, "lon": 71.4191, "name": "Multan"},
    {"icao": "OPPS", "lat": 33.9939, "lon": 71.5147, "name": "Peshawar"},
    {"icao": "OPQT", "lat": 30.2514, "lon": 66.9378, "name": "Quetta"},
    {"icao": "OPGD", "lat": 25.2333, "lon": 62.3294, "name": "Gwadar"},
    {"icao": "OPKD", "lat": 25.3181, "lon": 68.3661, "name": "Hyderabad"},
  ];

  /// Calculate distance between two coordinates in km (Haversine formula)
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * (pi / 180);

  /// Get ICAO code if location is within 20km of an airport
  String? icaoFromCoordinates(double lat, double lon) {
    for (final airport in _airports) {
      final distance = _calculateDistance(
          lat, lon, airport["lat"] as double, airport["lon"] as double);
      if (distance <= 20.0) {
        return airport["icao"] as String;
      }
    }
    return null;
  }

  String? icaoFromCity(String city) {
    city = city.toUpperCase();

    if (city.contains("ISLAMABAD") || city.contains("RAWALPINDI"))
      return "OPIS";
    if (city.contains("LAHORE")) return "OPLA";
    if (city.contains("FAISAL")) return "OPFA";
    if (city.contains("KARACHI")) return "OPKC";
    if (city.contains("SIALKOT")) return "OPST";
    if (city.contains("MULTAN")) return "OPMT";
    if (city.contains("PESHAWAR")) return "OPPS";
    if (city.contains("QUETTA")) return "OPQT";
    if (city.contains("GWADAR")) return "OPGD";
    if (city.contains("HYDERABAD")) return "OPKD";

    return null;
  }

  String _mapWindDegreesToCardinal(int? degrees) {
    if (degrees == null || degrees == -1 || degrees == 0) return '--';

    const directions = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSW',
      'SW',
      'WSW',
      'W',
      'WNW',
      'NW',
      'NNW'
    ];
    final index = (((degrees % 360) / 22.5) + 0.5).floor() % 16;
    return directions[index];
  }

  String _extractPrimaryMetarCode(String metarRawText) {
    metarRawText = metarRawText.toUpperCase();

    if (metarRawText.contains("TSRA")) return "TSRA";
    if (metarRawText.contains("TS")) return "TS";
    if (metarRawText.contains("SHRA")) return "SHRA";
    if (metarRawText.contains("RA")) return "RA";
    if (metarRawText.contains("SN")) return "SN";
    if (metarRawText.contains("DZ")) return "DZ";
    if (metarRawText.contains("FG")) return "FG";
    if (metarRawText.contains("BR")) return "BR";
    if (metarRawText.contains("HZ")) return "HZ";
    if (metarRawText.contains("FU")) return "FU";
    if (metarRawText.contains("DU")) return "DU";
    if (metarRawText.contains("SA")) return "SA";
    if (metarRawText.contains("OVC")) return "OVC";
    if (metarRawText.contains("BKN")) return "BKN";
    if (metarRawText.contains("SCT")) return "SCT";
    if (metarRawText.contains("FEW")) return "FEW";

    return "SKC";
  }

  /// Load weather by city name - NOW AWAITS PROPERLY FOR WINDY FIX
  Future<void> loadByCity(String city) async {
    lastCitySearched = city;

    final isIcao = RegExp(r'^[A-Za-z]{4}$').hasMatch(city.trim());
    final icao = icaoFromCity(city);

    // Show cached data instantly if available
    await loadCachedWeather();

    // Fetch API data - AWAIT instead of .then() for proper sequencing
    final json = await OpenMeteoService.fetchWeatherByCity(city);

    if (json != null) {
      rawWeatherJson = json;
      _parseForecastsOnly(json);
      await saveWeatherToCache(json);
    }

    // If direct ICAO code entered, use METAR for current weather
    if (isIcao) {
      final m = await fetchMetar(city.toUpperCase());
      if (m != null) {
        metar = m;
        _createCurrentFromMetarOnly(m);
        metarApplied = true;
        onDataLoaded?.call();
        return;
      }
    }

    // If major Pakistani city, use METAR for current weather
    if (icao != null) {
      final m = await fetchMetar(icao);
      if (m != null) {
        metar = m;
        _createCurrentFromMetarOnly(m);
        metarApplied = true;
        onDataLoaded?.call();
        return;
      }
    }

    // Otherwise use API data for current weather
    if (json != null) {
      _parseCurrentWeather(json);
    }

    metarApplied = false;
    metar = null;
    onDataLoaded?.call();
  }

  /// Load weather by coordinates
  Future<void> loadByCoordinates(double lat, double lon,
      {String? cityName}) async {
    lastCitySearched = cityName;

    final icao = icaoFromCoordinates(lat, lon);
    final json = await OpenMeteoService.fetchWeather(lat, lon);

    if (json != null) {
      if (cityName != null) {
        json['_city_name'] = cityName;
      }
      rawWeatherJson = json;
      _parseForecastsOnly(json);
      await saveWeatherToCache(json);

      if (icao != null) {
        final m = await fetchMetar(icao);
        if (m != null) {
          metar = m;
          _createCurrentFromMetarOnly(m);
          metarApplied = true;
          onDataLoaded?.call();
          return;
        }
      }

      _parseCurrentWeather(json);
      metarApplied = false;
      metar = null;
      onDataLoaded?.call();
    }
  }

  Future<void> loadByLocation() async {
    try {
      final position = await determinePosition();
      final lat = position.latitude;
      final lon = position.longitude;

      final icao = icaoFromCoordinates(lat, lon);
      final json = await OpenMeteoService.fetchWeather(lat, lon);

      if (json != null) {
        rawWeatherJson = json;
        _parseForecastsOnly(json);
        await saveWeatherToCache(json);

        if (icao != null) {
          final m = await fetchMetar(icao);
          if (m != null) {
            metar = m;
            _createCurrentFromMetarOnly(m);
            metarApplied = true;
            onDataLoaded?.call();
            return;
          }
        }

        _parseCurrentWeather(json);
        metarApplied = false;
        metar = null;
        onDataLoaded?.call();
      }
    } catch (e) {
      print('loadByLocation error: $e');
      rethrow;
    }
  }

  /// Get current coordinates (lat, lon)
  (double, double)? getCurrentCoordinates() {
    final c = current.value;
    if (c != null && c.lat != 0.0 && c.lon != 0.0) {
      return (c.lat, c.lon);
    }
    if (rawWeatherJson != null) {
      final lat = (rawWeatherJson?['latitude'] as num?)?.toDouble();
      final lon = (rawWeatherJson?['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        return (lat, lon);
      }
    }
    return null;
  }

  void _parseForecastsOnly(Map<String, dynamic> json) {
    final hourlyData = json["hourly"];
    final dailyData = json["daily"];

    daily = [];
    if (dailyData != null) {
      final times = dailyData["time"] as List? ?? [];
      final maxTemps = dailyData["temperature_2m_max"] as List? ?? [];
      final minTemps = dailyData["temperature_2m_min"] as List? ?? [];
      final weatherCodes = dailyData["weather_code"] as List? ?? [];
      final sunrises = dailyData["sunrise"] as List? ?? [];
      final sunsets = dailyData["sunset"] as List? ?? [];
      final uvIndexMaxList = dailyData["uv_index_max"] as List? ?? [];
      final precipSumList = dailyData["precipitation_sum"] as List? ?? [];
      final precipProbList =
          dailyData["precipitation_probability_max"] as List? ?? [];
      final windGustsMaxList = dailyData["wind_gusts_10m_max"] as List? ?? [];
      final windDirDomList =
          dailyData["wind_direction_10m_dominant"] as List? ?? [];

      for (int i = 0; i < times.length && i < 7; i++) {
        final code = weatherCodes.length > i ? weatherCodes[i] : 0;
        final minT = minTemps.length > i ? _toD(minTemps[i]) : 0.0;
        final maxT = maxTemps.length > i ? _toD(maxTemps[i]) : 0.0;
        daily.add(DailyWeather(
          date: times[i] ?? "--",
          maxTemp: maxT,
          minTemp: minT,
          condition: OpenMeteoService.getWeatherDescription(code),
          icon: OpenMeteoService.getWeatherIcon(code, true),
          sunrise: sunrises.length > i ? _formatTime(sunrises[i]) : "--",
          sunset: sunsets.length > i ? _formatTime(sunsets[i]) : "--",
          uvIndexMax:
              uvIndexMaxList.length > i ? _toD(uvIndexMaxList[i]) : null,
          precipitationSum:
              precipSumList.length > i ? _toD(precipSumList[i]) : null,
          precipitationProbability:
              precipProbList.length > i ? _toI(precipProbList[i]) : null,
          windGustsMax:
              windGustsMaxList.length > i ? _toD(windGustsMaxList[i]) : null,
          windDirectionDominant:
              windDirDomList.length > i ? _toI(windDirDomList[i]) : null,
        ));
      }
    }

    hourly = [];
    if (hourlyData != null) {
      final times = hourlyData["time"] as List? ?? [];
      final temps = hourlyData["temperature_2m"] as List? ?? [];
      final humidities = hourlyData["relative_humidity_2m"] as List? ?? [];
      final weatherCodes = hourlyData["weather_code"] as List? ?? [];
      final isDayList = hourlyData["is_day"] as List? ?? [];

      final now = DateTime.now();
      for (int i = 0; i < times.length; i++) {
        final timeStr = times[i];
        if (timeStr == null) continue;

        final timeStamp = DateTime.tryParse(timeStr);
        if (timeStamp == null) continue;

        if (timeStamp.isAfter(now.subtract(const Duration(minutes: 60)))) {
          final code = weatherCodes.length > i ? weatherCodes[i] : 0;
          final isDayHour = isDayList.length > i ? isDayList[i] == 1 : true;

          hourly.add(HourlyWeather(
            time: timeStamp.hour > 12
                ? "${timeStamp.hour - 12} PM"
                : timeStamp.hour == 0
                    ? "12 AM"
                    : "${timeStamp.hour} AM",
            tempC: temps.length > i ? _toD(temps[i]) : 0.0,
            icon: OpenMeteoService.getWeatherIcon(code, isDayHour),
            humidity: humidities.length > i ? _toI(humidities[i]) : 0,
          ));
        }
      }
    }
  }

  void _parseCurrentWeather(Map<String, dynamic> json) {
    final cur = json["current"];

    if (cur == null) {
      current.value = null;
      return;
    }

    final weatherCode = cur["weather_code"] ?? 0;
    final isDay = cur["is_day"] == 1;
    final condition = OpenMeteoService.getWeatherDescription(weatherCode);
    final icon = OpenMeteoService.getWeatherIcon(weatherCode, isDay);

    final cityName = json["_city_name"] ?? lastCitySearched ?? "Unknown";

    current.value = CurrentWeather(
      city: cityName,
      tempC: _toD(cur["temperature_2m"]),
      condition: condition,
      icon: icon,
      humidity: _toI(cur["relative_humidity_2m"]),
      windKph: _toD(cur["wind_speed_10m"]),
      windDeg: _toI(cur["wind_direction_10m"]),
      feelsLikeC: _toD(cur["apparent_temperature"]),
      dewpointC: _toD(cur["dew_point_2m"]),
      pressureMb: _toD(cur["pressure_msl"]),
      visKm: null,
      gustKph: _toD(cur["wind_gusts_10m"]),
      isDay: cur["is_day"] ?? 1,
      lat: _toD(json["latitude"]),
      lon: _toD(json["longitude"]),
      uvIndex: _toD(cur["uv_index"]),
      cloudCover: _toI(cur["cloud_cover"]),
      precipitation: _toD(cur["precipitation"]),
      rain: _toD(cur["rain"]),
      snowfall: _toD(cur["snowfall"]),
    );
  }

  void _createCurrentFromMetarOnly(Map<String, dynamic> m) {
    String metarRawText = m["raw_text"]?.toString().toUpperCase() ?? "";
    String primaryCode = _extractPrimaryMetarCode(metarRawText);

    final finalIconUrl = weatherApiIconUrl(mapMetarIcon(primaryCode));
    final metarDescription = mapMetarCodeToDescription(primaryCode);

    final stationIcao = m["station"]?.toString().toUpperCase() ?? "";
    String cityName = lastCitySearched ?? "Unknown";
    double lat = _toD(m["latitude"]);
    double lon = _toD(m["longitude"]);

    for (final airport in _airports) {
      if (airport["icao"] == stationIcao) {
        cityName = airport["name"] as String;
        lat = airport["lat"] as double;
        lon = airport["lon"] as double;
        break;
      }
    }

    int isDay = _calculateIsDay();

    current.value = CurrentWeather(
      city: cityName,
      tempC: _toD(m["temp_c"]),
      condition: metarDescription,
      icon: finalIconUrl,
      humidity: _toI(m["humidity"]),
      windKph: _toD(m["wind_kph"]),
      windDeg: _toI(m["wind_degrees"]),
      feelsLikeC: null,
      dewpointC: _toD(m["dewpoint_c"]),
      pressureMb: _toD(m["pressure_hpa"]),
      visKm: _toD(m["visibility_km"]),
      gustKph: null,
      isDay: isDay,
      lat: lat,
      lon: lon,
      uvIndex: null,
      cloudCover: null,
      precipitation: null,
      rain: null,
      snowfall: null,
    );
  }

  int _calculateIsDay() {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;
    final currentTimeInMinutes = currentHour * 60 + currentMinute;

    if (daily.isNotEmpty) {
      try {
        final today = daily.first;

        if (today.sunrise != "--" && today.sunset != "--") {
          final sunriseMinutes = _parseTimeToMinutes(today.sunrise);
          final sunsetMinutes = _parseTimeToMinutes(today.sunset);

          if (sunriseMinutes != null && sunsetMinutes != null) {
            if (currentTimeInMinutes >= sunriseMinutes &&
                currentTimeInMinutes < sunsetMinutes) {
              return 1;
            } else {
              return 0;
            }
          }
        }
      } catch (e) {
        print('Error parsing sunrise/sunset: $e');
      }
    }

    if (currentHour >= 6 && currentHour < 18) {
      return 1;
    } else {
      return 0;
    }
  }

  int? _parseTimeToMinutes(String timeStr) {
    try {
      final parts = timeStr.trim().split(" ");
      if (parts.length != 2) return null;

      final timePart = parts[0];
      final amPm = parts[1].toUpperCase();

      final hm = timePart.split(":");
      if (hm.length != 2) return null;

      int hour = int.tryParse(hm[0]) ?? 0;
      int minute = int.tryParse(hm[1]) ?? 0;

      if (amPm == "PM" && hour != 12) {
        hour += 12;
      } else if (amPm == "AM" && hour == 12) {
        hour = 0;
      }

      return hour * 60 + minute;
    } catch (e) {
      return null;
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return "--";
    try {
      final dt = DateTime.parse(isoTime);
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      if (hour > 12) {
        return "${hour - 12}:$minute PM";
      } else if (hour == 0) {
        return "12:$minute AM";
      } else if (hour == 12) {
        return "12:$minute PM";
      } else {
        return "$hour:$minute AM";
      }
    } catch (e) {
      return "--";
    }
  }

  void applyMetarOverride() {
    if (metar == null || current.value == null) return;

    final m = metar!;
    String metarRawText = m["raw_text"]?.toString().toUpperCase() ?? "";
    String primaryCode = _extractPrimaryMetarCode(metarRawText);

    final finalIconUrl = weatherApiIconUrl(mapMetarIcon(primaryCode));
    final metarDescription = mapMetarCodeToDescription(primaryCode);

    current.value = CurrentWeather(
      city: current.value!.city,
      tempC:
          _toD(m["temp_c"]) != 0.0 ? _toD(m["temp_c"]) : current.value!.tempC,
      condition: metarDescription,
      icon: finalIconUrl,
      humidity: _toI(m["humidity"]) != 0
          ? _toI(m["humidity"])
          : current.value!.humidity,
      windKph: _toD(m["wind_kph"]) != 0.0
          ? _toD(m["wind_kph"])
          : current.value!.windKph,
      windDeg: _toI(m["wind_degrees"]) != 0
          ? _toI(m["wind_degrees"])
          : current.value!.windDeg,
      feelsLikeC: current.value!.feelsLikeC,
      dewpointC: _toD(m["dewpoint_c"]) != 0.0
          ? _toD(m["dewpoint_c"])
          : current.value!.dewpointC,
      pressureMb: _toD(m["pressure_hpa"]) != 0.0
          ? _toD(m["pressure_hpa"])
          : current.value!.pressureMb,
      visKm: _toD(m["visibility_km"]) != 0.0
          ? _toD(m["visibility_km"])
          : current.value!.visKm,
      gustKph: current.value!.gustKph,
      isDay: current.value!.isDay,
      lat: current.value!.lat,
      lon: current.value!.lon,
      uvIndex: current.value!.uvIndex,
      cloudCover: current.value!.cloudCover,
      precipitation: current.value!.precipitation,
      rain: current.value!.rain,
      snowfall: current.value!.snowfall,
    );
  }

  Map<String, String> getTilesForUI() {
    if (current.value == null) return {};

    if (metarApplied && metar != null) {
      final m = metar!;
      final metarWindDir = _mapWindDegreesToCardinal(_toI(m["wind_degrees"]));

      return {
        "Humidity": "${m["humidity"] ?? "--"}%",
        "Dew Point": "${m["dewpoint_c"] ?? "--"}°C",
        "Pressure": "${m["pressure_hpa"] ?? "--"} hPa",
        "Visibility": "${m["visibility_km"] ?? "--"} km",
        "Wind Speed": "${m["wind_kph"] ?? "--"} km/h",
        "Wind Dir": metarWindDir,
      };
    }

    return {
      "Feels Like":
          "${current.value!.feelsLikeC?.toStringAsFixed(1) ?? '--'}°C",
      "Humidity": "${current.value!.humidity}%",
      "Dew Point": "${current.value!.dewpointC?.toStringAsFixed(1) ?? '--'}°C",
      "Pressure":
          "${current.value!.pressureMb?.toStringAsFixed(0) ?? '--'} hPa",
      "Wind Speed":
          "${current.value!.gustKph?.toStringAsFixed(0) ?? '--'} km/h",
      "Wind Dir": _mapWindDegreesToCardinal(current.value!.windDeg),
      "UV Index": "${current.value!.uvIndex?.toStringAsFixed(1) ?? '--'}",
      "Cloud Cover": "${current.value!.cloudCover ?? '--'}%",
      "Precipitation":
          "${current.value!.precipitation?.toStringAsFixed(1) ?? '0'} mm",
    };
  }
}
