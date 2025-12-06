// lib/services/metar_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../secrets.dart';

final Map<String, Map<String, dynamic>> _metarCache = {};
const Duration _ttl = Duration(minutes: 20);

String _nowIso() => DateTime.now().toIso8601String();

double _toDouble(dynamic v) {
  if (v == null) return double.nan;
  if (v is num) return v.toDouble();
  try {
    return double.parse(v.toString());
  } catch (_) {
    return double.nan;
  }
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  try {
    return int.parse(v.toString());
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> fetchMetar(String icao) async {
  icao = icao.toUpperCase();

  // Return from cache if fresh
  if (_metarCache.containsKey(icao)) {
    final diff = DateTime.now()
        .difference(DateTime.parse(_metarCache[icao]!["fetched_at"]));
    if (diff < _ttl) {
      return _metarCache[icao]!["data"];
    }
  }

  final url = Uri.parse("https://api.checkwx.com/metar/$icao/decoded");

  try {
    final response = await http.get(
      url,
      headers: {"X-API-Key": checkwxApiKey},
    );

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded["results"] == 0) return null;

    final raw = decoded["data"][0];

    final clean = {
      "station": raw["icao"] ?? icao,
      "raw_text": raw["raw_text"] ?? "--",
      "temp_c": _toDouble(raw["temperature"]?["celsius"]),
      "dewpoint_c": _toDouble(raw["dewpoint"]?["celsius"]),
      "pressure_hpa": _toDouble(raw["barometer"]?["hpa"]),
      "wind_kph": _toDouble(raw["wind"]?["speed_kph"]),
      "wind_degrees": _toInt(raw["wind"]?["degrees"]),
      "humidity": _toInt(raw["humidity"]?["percent"]),
      "visibility_km": _toDouble(raw["visibility"]?["meters"]) / 1000.0,
      "condition_code": raw["flight_category"] ?? "",
      "condition_text": raw["wx_string"] ?? "",
      "observed": raw["observed"] ?? _nowIso(),
    };

    // Cache it
    _metarCache[icao] = {
      "fetched_at": _nowIso(),
      "data": clean,
    };

    return clean;
  } catch (e) {
    return null;
  }
}
