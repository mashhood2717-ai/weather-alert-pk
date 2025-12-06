// lib/metar_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secrets.dart';

final Map<String, Map<String, dynamic>> _metarCache = {};
final Duration _ttl = Duration(minutes: 20);

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
    final r = await http.get(Uri.parse(url), headers: {
      'X-API-Key': checkwxApiKey,
    });

    if (r.statusCode != 200) return null;

    final json = jsonDecode(r.body);
    if (json == null || json['data'] == null || json['data'].isEmpty) {
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
