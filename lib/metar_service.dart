// lib/metar_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'secrets.dart';

final Map<String, Map<String, dynamic>> _metarCache = {};
final Duration _ttl = Duration(minutes: 20);

// Worker URL for cached METAR
const String _workerUrl = 'https://travel-weather-api.mashhood2717.workers.dev';

/// Clear the METAR cache (call when loading new route)
void clearMetarCache() {
  _metarCache.clear();
  debugPrint('🧹 METAR cache cleared');
}

double _toDouble(dynamic v) {
  if (v == null) return double.nan;
  if (v is num) return v.toDouble();
  try {
    return double.parse(v.toString());
  } catch (_) {
    return double.nan;
  }
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

/// Check if location is in METAR range and return METAR data from worker
/// Returns null if not in range or error
Future<Map<String, dynamic>?> fetchMetarFromWorker(
    double lat, double lon) async {
  try {
    debugPrint('🛫 Checking METAR coverage for ($lat, $lon) from worker...');
    final response = await http
        .get(
          Uri.parse('$_workerUrl/nearest-airport?lat=$lat&lon=$lon'),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      debugPrint('❌ Worker error: ${response.statusCode}');
      return null;
    }

    final data = jsonDecode(response.body);

    if (data['in_metar_range'] != true) {
      debugPrint('📍 Location outside METAR range: ${data['message']}');
      return null;
    }

    final metar = data['metar'];
    if (metar == null || metar['error'] != null) {
      debugPrint('❌ No METAR data available');
      return null;
    }

    debugPrint(
        '✅ METAR from worker: ${metar['airport_name']} (${metar['icao']})');

    // Convert worker format to clean format expected by the app
    final clean = {
      'station': metar['icao'] ?? '--',
      'airport_name': metar['airport_name'] ?? '--',
      'temp_c': metar['temp_c']?.toString() ?? '--',
      'dewpoint_c': metar['dewpoint_c']?.toString() ?? '--',
      'pressure_hpa': metar['pressure_hpa']?.toString() ?? '--',
      'visibility_km': metar['visibility_km']?.toString() ?? '--',
      'humidity': metar['humidity'] ?? '--',
      'wind_kph': metar['wind_kph']?.toString() ?? '--',
      'wind_degrees': metar['wind_degrees'] ?? '--',
      'condition_code': _extractConditionCode(metar['conditions']),
      'condition_text':
          _extractConditionText(metar['conditions'], metar['clouds']),
      'raw_text': metar['raw_text'] ?? '--',
      'observed': metar['observed'] ?? _nowIso(),
      'flight_category': metar['flight_category'] ?? '--',
      'from_worker': true,
    };

    return clean;
  } catch (e) {
    debugPrint('❌ Worker METAR error: $e');
    return null;
  }
}

/// Extract condition code from METAR conditions array
String _extractConditionCode(dynamic conditions) {
  if (conditions == null || conditions is! List || conditions.isEmpty) {
    return 'SKC';
  }
  return conditions[0]['code']?.toString() ?? 'SKC';
}

/// Extract condition text from METAR conditions/clouds
String _extractConditionText(dynamic conditions, dynamic clouds) {
  if (conditions != null && conditions is List && conditions.isNotEmpty) {
    return conditions[0]['text']?.toString() ?? 'Clear';
  }
  if (clouds != null && clouds is List && clouds.isNotEmpty) {
    return clouds[0]['text']?.toString() ?? 'Clear';
  }
  return 'Clear';
}

/// ------------------------------
/// CLEAN METAR FORMAT (UI-READY)
/// ------------------------------
Future<Map<String, dynamic>?> fetchMetar(String icao) async {
  final key = icao.toUpperCase().trim();

  // CACHE
  if (_metarCache[key] != null) {
    final old = _metarCache[key]!;
    final t = DateTime.parse(old['fetched_at']);
    if (DateTime.now().difference(t) < _ttl) {
      return old['data'];
    }
  }

  final url = 'https://api.checkwx.com/metar/$key/decoded';
  try {
    debugPrint('🛫 Fetching METAR for $key from CheckWX...');
    final r = await http.get(Uri.parse(url), headers: {
      'X-API-Key': checkwxApiKey,
    });

    if (r.statusCode != 200) {
      debugPrint('❌ METAR API error for $key: ${r.statusCode}');
      return null;
    }

    final json = jsonDecode(r.body);
    if (json == null || json['data'] == null || json['data'].isEmpty) {
      debugPrint('❌ METAR no data for $key');
      return null;
    }

    final raw = json['data'][0];

    // ------------------------------
    // CLEAN FIELD EXTRACTION
    // ------------------------------
    final tempC = _toDouble(raw['temperature']?['celsius']);
    final dewC = _toDouble(raw['dewpoint']?['celsius']);
    final pressureHpa = _toDouble(raw['barometer']?['hpa']);

    // visibility meters → km
    final visMeters = _toDouble(raw['visibility']?['meters']);
    final visKm = visMeters.isNaN ? double.nan : (visMeters / 1000.0);

    final humidity = raw['humidity']?['percent'];
    final windKph = _toDouble(raw['wind']?['speed_kph']);
    final windDeg = raw['wind']?['degrees'];

    // conditions
    String condCode = '--';
    String condText = '--';
    if (raw['conditions'] != null &&
        raw['conditions'] is List &&
        raw['conditions'].isNotEmpty) {
      condCode = raw['conditions'][0]['code'] ?? '--';
      condText = raw['conditions'][0]['text'] ?? '--';
    }

    // ------------------------------
    // FINAL UI-READY CLEAN OBJECT
    // ------------------------------
    final clean = {
      'station': key,
      'temp_c': tempC.isNaN ? '--' : tempC.toStringAsFixed(1),
      'dewpoint_c': dewC.isNaN ? '--' : dewC.toStringAsFixed(1),
      'pressure_hpa': pressureHpa.isNaN ? '--' : pressureHpa.toStringAsFixed(0),
      'visibility_km': visKm.isNaN ? '--' : visKm.toStringAsFixed(1),
      'humidity': humidity ?? '--',
      'wind_kph': windKph.isNaN ? '--' : windKph.toStringAsFixed(1),
      'wind_degrees': windDeg ?? '--',
      'condition_code': condCode,
      'condition_text': condText,
      'raw_text': raw['raw_text'] ?? '--',
      'observed': raw['observed'] ?? _nowIso(),
    };

    _metarCache[key] = {
      'fetched_at': _nowIso(),
      'data': clean,
    };

    return clean;
  } catch (_) {
    return null;
  }
}
