// lib/services/weather_controller.dart
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../metar_service.dart';
import '../services/open_meteo_service.dart';
import '../services/geocoding_service.dart';
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

  /// True if current weather is from GPS location, false if from search
  bool isFromCurrentLocation = false;

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

  // Pakistan airports with coordinates (lat, lon, ICAO) and custom radius
  // Updated coordinates for new Islamabad International Airport
  static const List<Map<String, dynamic>> _airports = [
    {
      "icao": "OPIS",
      "lat": 33.5605,
      "lon": 72.8495,
      "name": "Islamabad",
      "radius": 40.0
    },
    {
      "icao": "OPLA",
      "lat": 31.5216,
      "lon": 74.4036,
      "name": "Lahore",
      "radius": 30.0
    },
    {
      "icao": "OPFA",
      "lat": 31.3650,
      "lon": 72.9950,
      "name": "Faisalabad",
      "radius": 30.0
    },
    {
      "icao": "OPKC",
      "lat": 24.9065,
      "lon": 67.1608,
      "name": "Karachi",
      "radius": 40.0
    }, // 40km - large metro
    {
      "icao": "OPST",
      "lat": 32.5356,
      "lon": 74.3639,
      "name": "Sialkot",
      "radius": 30.0
    },
    {
      "icao": "OPMT",
      "lat": 30.2032,
      "lon": 71.4191,
      "name": "Multan",
      "radius": 30.0
    },
    {
      "icao": "OPPS",
      "lat": 33.9939,
      "lon": 71.5147,
      "name": "Peshawar",
      "radius": 30.0
    },
    {
      "icao": "OPQT",
      "lat": 30.2514,
      "lon": 66.9378,
      "name": "Quetta",
      "radius": 30.0
    },
    {
      "icao": "OPGD",
      "lat": 25.2333,
      "lon": 62.3294,
      "name": "Gwadar",
      "radius": 30.0
    },
    {
      "icao": "OPKD",
      "lat": 25.3181,
      "lon": 68.3661,
      "name": "Hyderabad",
      "radius": 30.0
    },
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

  /// Get ICAO code and airport info if location is within airport's radius
  /// Returns null if no airport nearby, otherwise returns airport data with distance
  Map<String, dynamic>? getAirportFromCoordinates(double lat, double lon) {
    Map<String, dynamic>? nearestAirport;
    double nearestDistance = double.infinity;

    for (final airport in _airports) {
      final airportRadius = (airport["radius"] as double?) ?? 30.0;
      final distance = _calculateDistance(
          lat, lon, airport["lat"] as double, airport["lon"] as double);
      if (distance <= airportRadius && distance < nearestDistance) {
        nearestAirport = {
          "icao": airport["icao"],
          "lat": airport["lat"],
          "lon": airport["lon"],
          "name": airport["name"],
          "radius": airportRadius,
          "distance": distance,
        };
        nearestDistance = distance;
      }
    }
    return nearestAirport;
  }

  /// Get the nearest airport within a maximum distance (for travel routes)
  /// This is less strict than getAirportFromCoordinates which uses airport-specific radii
  Map<String, dynamic>? getNearestAirport(double lat, double lon,
      {double maxDistanceKm = 100}) {
    Map<String, dynamic>? nearestAirport;
    double nearestDistance = double.infinity;

    for (final airport in _airports) {
      final distance = _calculateDistance(
          lat, lon, airport["lat"] as double, airport["lon"] as double);
      if (distance <= maxDistanceKm && distance < nearestDistance) {
        final airportRadius = (airport["radius"] as double?) ?? 30.0;
        nearestAirport = {
          "icao": airport["icao"],
          "lat": airport["lat"],
          "lon": airport["lon"],
          "name": airport["name"],
          "radius": airportRadius,
          "distance": distance,
        };
        nearestDistance = distance;
      }
    }
    return nearestAirport;
  }

  /// Get ICAO code if location is within airport's custom radius
  String? icaoFromCoordinates(double lat, double lon) {
    final airport = getAirportFromCoordinates(lat, lon);
    return airport?["icao"] as String?;
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
    isFromCurrentLocation = false; // This is a search, not GPS location

    // Show cached data instantly if available
    await loadCachedWeather();

    // Fetch API data - AWAIT instead of .then() for proper sequencing
    final json = await OpenMeteoService.fetchWeatherByCity(city);

    if (json != null) {
      rawWeatherJson = json;
      _parseForecastsOnly(json);
      await saveWeatherToCache(json);

      // Get coordinates from the geocoded result
      final lat = _toD(json['latitude']);
      final lon = _toD(json['longitude']);

      // Try worker METAR first (cached, no API calls)
      if (lat != 0.0 && lon != 0.0) {
        final workerMetar = await fetchMetarFromWorker(lat, lon);
        if (workerMetar != null) {
          metar = workerMetar;
          _currentUserLat = lat;
          _currentUserLon = lon;
          _createCurrentFromMetarOnly(workerMetar, userLat: lat, userLon: lon);
          metarApplied = true;
          debugPrint('✅ Using WORKER METAR for city: $city');
          await _fetchAndUpdateStreetAddress(lat, lon);
          onDataLoaded?.call();
          return;
        }
      }

      // Outside METAR range - use Open-Meteo (free)
      debugPrint('📍 City outside METAR range - using Open-Meteo (free)');
      _parseCurrentWeather(json);
      metarApplied = false;
      metar = null;
      if (lat != 0.0 && lon != 0.0) {
        await _fetchAndUpdateStreetAddress(lat, lon);
      }
      onDataLoaded?.call();
    }
  }

  /// Load weather by coordinates (from search/favorites - not GPS)
  Future<void> loadByCoordinates(double lat, double lon,
      {String? cityName, bool isCurrentLocation = false}) async {
    lastCitySearched = cityName;
    isFromCurrentLocation = isCurrentLocation;

    final json = await OpenMeteoService.fetchWeather(lat, lon);

    if (json != null) {
      if (cityName != null) {
        json['_city_name'] = cityName;
      }
      rawWeatherJson = json;
      _parseForecastsOnly(json);
      await saveWeatherToCache(json);

      // Try worker METAR first (cached, no API calls)
      final workerMetar = await fetchMetarFromWorker(lat, lon);
      if (workerMetar != null) {
        metar = workerMetar;
        _currentUserLat = lat;
        _currentUserLon = lon;
        _createCurrentFromMetarOnly(workerMetar, userLat: lat, userLon: lon);
        metarApplied = true;
        debugPrint('✅ Using WORKER METAR for current weather');
        await _fetchAndUpdateStreetAddress(lat, lon);
        onDataLoaded?.call();
        return;
      }

      // Outside METAR range - use Open-Meteo (free)
      debugPrint('📍 Outside METAR range - using Open-Meteo (free)');
      _parseCurrentWeather(json);
      metarApplied = false;
      metar = null;
      await _fetchAndUpdateStreetAddress(lat, lon);
      onDataLoaded?.call();
    }
  }

  Future<void> loadByLocation() async {
    try {
      isFromCurrentLocation = true; // This is GPS location

      final position = await determinePosition();
      final lat = position.latitude;
      final lon = position.longitude;

      final json = await OpenMeteoService.fetchWeather(lat, lon);

      if (json != null) {
        rawWeatherJson = json;
        _parseForecastsOnly(json);
        await saveWeatherToCache(json);

        // Try worker METAR first (cached, no API calls)
        final workerMetar = await fetchMetarFromWorker(lat, lon);
        if (workerMetar != null) {
          metar = workerMetar;
          _currentUserLat = lat;
          _currentUserLon = lon;
          _createCurrentFromMetarOnly(workerMetar, userLat: lat, userLon: lon);
          metarApplied = true;
          debugPrint('✅ Using WORKER METAR for GPS location');
          await _fetchAndUpdateStreetAddress(lat, lon, forceUpdateCity: true);
          onDataLoaded?.call();
          return;
        }

        // Outside METAR range - use Open-Meteo (free)
        debugPrint('📍 GPS outside METAR range - using Open-Meteo (free)');
        _parseCurrentWeather(json);
        metarApplied = false;
        metar = null;
        await _fetchAndUpdateStreetAddress(lat, lon, forceUpdateCity: true);
        onDataLoaded?.call();
      }
    } catch (e) {
      print('loadByLocation error: $e');
      rethrow;
    }
  }

  /// Fetch street address from geocoding and update current weather
  Future<void> _fetchAndUpdateStreetAddress(double lat, double lon,
      {bool forceUpdateCity = false}) async {
    try {
      final result = await GeocodingService.reverseGeocode(lat, lon);
      if (result != null && current.value != null) {
        // Update city name if current city is "Unknown", generic, or force update requested
        String? newCityName;
        final currentCity = current.value!.city;

        // Get the geocoded main location (has special Rawalpindi handling)
        final mainLocation = result.mainLocationName;

        // Force update for GPS locations, or if current city is generic
        final shouldUpdateCity = forceUpdateCity ||
            currentCity == 'Unknown' ||
            currentCity.isEmpty ||
            currentCity.startsWith('Lat:');

        // Special case: Always prefer Rawalpindi over Islamabad
        // If geocoding says Rawalpindi but city shows Islamabad, update it
        final isCurrentIslamabad = currentCity.toLowerCase() == 'islamabad';
        final isGeocodedRawalpindi = mainLocation.toLowerCase() == 'rawalpindi';

        if (shouldUpdateCity || (isCurrentIslamabad && isGeocodedRawalpindi)) {
          if (mainLocation != 'Unknown') {
            newCityName = mainLocation;
          }
        }

        current.value = current.value!.copyWithAddress(
          city: newCityName,
          streetAddress: result.shortAddress,
          fullAddress: result.formattedAddress,
        );
      }
    } catch (e) {
      print('Geocoding error: $e');
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

      // Parse hourly data for day/night icon calculation
      final hourlyTimes = hourlyData?["time"] as List? ?? [];
      final hourlyCodes = hourlyData?["weather_code"] as List? ?? [];
      final hourlyTemps = hourlyData?["temperature_2m"] as List? ?? [];

      for (int i = 0; i < times.length && i < 7; i++) {
        final code = weatherCodes.length > i ? weatherCodes[i] : 0;
        final minT = minTemps.length > i ? _toD(minTemps[i]) : 0.0;
        final maxT = maxTemps.length > i ? _toD(maxTemps[i]) : 0.0;
        final sunriseStr = sunrises.length > i ? sunrises[i] : null;
        final sunsetStr = sunsets.length > i ? sunsets[i] : null;
        final dateStr = times[i] ?? "--";

        // Calculate day/night dominant icons from hourly data
        final dayNightData = _calculateDayNightIcons(
          dateStr: dateStr,
          sunriseStr: sunriseStr,
          sunsetStr: sunsetStr,
          hourlyTimes: hourlyTimes,
          hourlyCodes: hourlyCodes,
          hourlyTemps: hourlyTemps,
        );

        // Use precipitation-priority icon for main daily display
        final dominantIcon = dayNightData['dominantIcon'] as String? ??
            OpenMeteoService.getWeatherIcon(code, true);
        final dominantCondition =
            dayNightData['dominantCondition'] as String? ??
                OpenMeteoService.getWeatherDescription(code);

        daily.add(DailyWeather(
          date: dateStr,
          maxTemp: maxT,
          minTemp: minT,
          condition: dominantCondition,
          icon: dominantIcon,
          sunrise: sunriseStr != null ? _formatTime(sunriseStr) : "--",
          sunset: sunsetStr != null ? _formatTime(sunsetStr) : "--",
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
          dayIcon: dayNightData['dayIcon'] as String?,
          dayCondition: dayNightData['dayCondition'] as String?,
          dayHighTemp: dayNightData['dayHighTemp'] as double?,
          nightIcon: dayNightData['nightIcon'] as String?,
          nightCondition: dayNightData['nightCondition'] as String?,
          nightLowTemp: dayNightData['nightLowTemp'] as double?,
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

  /// Calculate day/night dominant icons from hourly data
  /// Precipitation (rain, snow, thunderstorm) takes priority
  /// Otherwise, the most frequently occurring condition wins
  Map<String, dynamic> _calculateDayNightIcons({
    required String dateStr,
    required String? sunriseStr,
    required String? sunsetStr,
    required List hourlyTimes,
    required List hourlyCodes,
    required List hourlyTemps,
  }) {
    if (dateStr == "--" || sunriseStr == null || sunsetStr == null) {
      return {};
    }

    final date = DateTime.tryParse(dateStr);
    final sunrise = DateTime.tryParse(sunriseStr);
    final sunset = DateTime.tryParse(sunsetStr);

    if (date == null || sunrise == null || sunset == null) {
      return {};
    }

    // Precipitation weather codes (priority conditions)
    // 51-67: Drizzle/Rain, 71-77: Snow, 80-82: Rain showers, 85-86: Snow showers, 95-99: Thunderstorm
    bool _isPrecipitation(int code) {
      return (code >= 51 && code <= 67) ||
          (code >= 71 && code <= 77) ||
          (code >= 80 && code <= 86) ||
          (code >= 95 && code <= 99);
    }

    // Day hours: sunrise to sunset
    List<int> dayCodes = [];
    List<double> dayTemps = [];

    // Night hours: before sunrise and after sunset (same day)
    List<int> nightCodes = [];
    List<double> nightTemps = [];

    for (int i = 0; i < hourlyTimes.length; i++) {
      final timeStr = hourlyTimes[i];
      if (timeStr == null) continue;

      final hourTime = DateTime.tryParse(timeStr);
      if (hourTime == null) continue;

      // Check if this hour belongs to this date
      if (hourTime.year != date.year ||
          hourTime.month != date.month ||
          hourTime.day != date.day) {
        continue;
      }

      final code = hourlyCodes.length > i ? _toI(hourlyCodes[i]) : 0;
      final temp = hourlyTemps.length > i ? _toD(hourlyTemps[i]) : 0.0;

      // Determine if day or night based on sunrise/sunset
      if (hourTime.isAfter(sunrise) && hourTime.isBefore(sunset)) {
        dayCodes.add(code);
        dayTemps.add(temp);
      } else {
        nightCodes.add(code);
        nightTemps.add(temp);
      }
    }

    // Calculate dominant icon for day (with precipitation priority)
    String? dayIcon;
    String? dayCondition;
    if (dayCodes.isNotEmpty) {
      final dominantDayCode = _getDominantCode(dayCodes, _isPrecipitation);
      dayIcon = OpenMeteoService.getWeatherIcon(dominantDayCode, true);
      dayCondition = OpenMeteoService.getWeatherDescription(dominantDayCode);
    }

    // Calculate dominant icon for night (with precipitation priority)
    String? nightIcon;
    String? nightCondition;
    if (nightCodes.isNotEmpty) {
      final dominantNightCode = _getDominantCode(nightCodes, _isPrecipitation);
      nightIcon = OpenMeteoService.getWeatherIcon(dominantNightCode, false);
      nightCondition =
          OpenMeteoService.getWeatherDescription(dominantNightCode);
    }

    // Calculate high/low for day and night
    double? dayHighTemp =
        dayTemps.isNotEmpty ? dayTemps.reduce((a, b) => a > b ? a : b) : null;
    double? nightLowTemp = nightTemps.isNotEmpty
        ? nightTemps.reduce((a, b) => a < b ? a : b)
        : null;

    // Calculate overall dominant icon for the main 7-day forecast display
    final allCodes = [...dayCodes, ...nightCodes];
    String? dominantIcon;
    String? dominantCondition;
    if (allCodes.isNotEmpty) {
      final dominantCode = _getDominantCode(allCodes, _isPrecipitation);
      dominantIcon = OpenMeteoService.getWeatherIcon(dominantCode, true);
      dominantCondition = OpenMeteoService.getWeatherDescription(dominantCode);
    }

    return {
      'dayIcon': dayIcon,
      'dayCondition': dayCondition,
      'dayHighTemp': dayHighTemp,
      'nightIcon': nightIcon,
      'nightCondition': nightCondition,
      'nightLowTemp': nightLowTemp,
      'dominantIcon': dominantIcon,
      'dominantCondition': dominantCondition,
    };
  }

  /// Get the dominant weather code with precipitation priority
  /// If any precipitation code exists, return the most common precipitation
  /// Otherwise return the most common code overall
  int _getDominantCode(List<int> codes, bool Function(int) isPrecipitation) {
    if (codes.isEmpty) return 0;

    // Separate precipitation and non-precipitation codes
    final precipCodes = codes.where(isPrecipitation).toList();

    // If there's any precipitation, prioritize it
    if (precipCodes.isNotEmpty) {
      return _getMostFrequent(precipCodes);
    }

    // Otherwise return most frequent code
    return _getMostFrequent(codes);
  }

  /// Get the most frequently occurring value in a list
  int _getMostFrequent(List<int> codes) {
    if (codes.isEmpty) return 0;

    final frequency = <int, int>{};
    for (final code in codes) {
      frequency[code] = (frequency[code] ?? 0) + 1;
    }

    int maxCount = 0;
    int mostFrequent = codes.first;
    frequency.forEach((code, count) {
      if (count > maxCount) {
        maxCount = count;
        mostFrequent = code;
      }
    });

    return mostFrequent;
  }

  void _parseCurrentWeather(Map<String, dynamic> json) {
    final cur = json["current"];

    if (cur == null) {
      current.value = null;
      return;
    }

    final weatherCode = cur["weather_code"] ?? 0;
    // Handle is_day as either int (0/1) or bool
    final isDayRaw = cur["is_day"];
    final isDay = isDayRaw == 1 || isDayRaw == true;
    print(
        '🌙 _parseCurrentWeather: isDayRaw=$isDayRaw (${isDayRaw.runtimeType}), isDay=$isDay, weatherCode=$weatherCode');
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
      isDay: isDay ? 1 : 0, // Use the parsed isDay boolean
      lat: _toD(json["latitude"]),
      lon: _toD(json["longitude"]),
      uvIndex: _toD(cur["uv_index"]),
      cloudCover: _toI(cur["cloud_cover"]),
      precipitation: _toD(cur["precipitation"]),
      rain: _toD(cur["rain"]),
      snowfall: _toD(cur["snowfall"]),
    );
  }

  // Store the current user location for METAR calculations
  double? _currentUserLat;
  double? _currentUserLon;

  void _createCurrentFromMetarOnly(Map<String, dynamic> m,
      {double? userLat, double? userLon}) {
    String metarRawText = m["raw_text"]?.toString().toUpperCase() ?? "";
    String primaryCode = _extractPrimaryMetarCode(metarRawText);

    // Calculate isDay FIRST before using it for icon
    int isDay = _calculateIsDay();

    // Pass isDay to icon functions for proper day/night icons
    final iconFile = mapMetarIcon(primaryCode, isDay: isDay == 1);
    final finalIconUrl = weatherApiIconUrl(iconFile, isDay: isDay == 1);
    final metarDescription = mapMetarCodeToDescription(primaryCode);

    final stationIcao = m["station"]?.toString().toUpperCase() ?? "";
    String cityName = lastCitySearched ?? "Unknown";

    // Get airport coordinates for METAR station
    double airportLat = 0.0;
    double airportLon = 0.0;

    for (final airport in _airports) {
      if (airport["icao"] == stationIcao) {
        airportLat = airport["lat"] as double;
        airportLon = airport["lon"] as double;
        break;
      }
    }

    // Use user's actual location if provided, otherwise fall back to airport location
    final displayLat = userLat ?? _currentUserLat ?? airportLat;
    final displayLon = userLon ?? _currentUserLon ?? airportLon;

    // Calculate distance from user to airport
    double? distanceToAirport;
    if (userLat != null && userLon != null && airportLat != 0.0) {
      distanceToAirport =
          _calculateDistance(userLat, userLon, airportLat, airportLon);
    } else if (_currentUserLat != null &&
        _currentUserLon != null &&
        airportLat != 0.0) {
      distanceToAirport = _calculateDistance(
          _currentUserLat!, _currentUserLon!, airportLat, airportLon);
    }

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
      lat: displayLat,
      lon: displayLon,
      uvIndex: null,
      cloudCover: null,
      precipitation: null,
      rain: null,
      snowfall: null,
      metarStation: stationIcao,
      metarLat: airportLat,
      metarLon: airportLon,
      metarDistanceKm: distanceToAirport,
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

    // Use existing isDay from current weather for proper day/night icons
    final isDay = current.value!.isDay == 1;
    final iconFile = mapMetarIcon(primaryCode, isDay: isDay);
    final finalIconUrl = weatherApiIconUrl(iconFile, isDay: isDay);
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
