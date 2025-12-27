// lib/services/wu_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../secrets.dart';

final Map<String, dynamic> _wuStationCache = {};
final Duration _wuTtl = Duration(minutes: 10);

String _nowIso() => DateTime.now().toUtc().toIso8601String();

Future<Map<String, dynamic>?> fetchWUCurrentByStation(String stationId) async {
  final key = stationId.trim().toUpperCase();

  if (_wuStationCache[key] != null) {
    try {
      final t = DateTime.parse(_wuStationCache[key]['fetched_at']);
      if (DateTime.now().difference(t) < _wuTtl) {
        return _wuStationCache[key]['data'];
      }
    } catch (_) {}
  }

  final url =
      "https://api.weather.com/v2/pws/observations/current?stationId=$key&format=json&units=m&apiKey=$wuApiKey";

  try {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) return null;

    final j = jsonDecode(r.body);
    if (j == null || j['observations'] == null || j['observations'].isEmpty) {
      return null;
    }

    final o = j['observations'][0];

    String pickIcon(dynamic icon) {
      if (icon == null) return '113.png';
      final s = icon.toString();
      if (RegExp(r'^\d+$').hasMatch(s)) return '113.png';
      if (s.toLowerCase() == 'unknown') return '113.png';
      if (s.contains('.png')) return s;
      return '113.png';
    }

    dynamic safe(v) => v ?? '--';

    final clean = {
      "station": safe(o["stationID"]),
      "temp_c": safe(o["metric"]?["temp"]),
      "dewpoint_c": safe(o["metric"]?["dewpt"]),
      "humidity": safe(o["humidity"]),
      "wind_kph": safe(o["metric"]?["windSpeed"]),
      "wind_degrees": safe(o["winddir"]),
      "pressure_hpa": safe(o["metric"]?["pressure"]),
      "condition_text": safe(o["conditions"]),
      "icon_code": pickIcon(o["icon"]),
      "observed": safe(o["obsTimeUtc"]),
      "rain_rate": safe(o["metric"]?["precipRate"]),
      "rain_total": safe(o["metric"]?["precipTotal"]),
      "lat": o["lat"],
      "lon": o["lon"],
      "neighborhood": safe(o["neighborhood"]),
    };

    _wuStationCache[key] = {"fetched_at": _nowIso(), "data": clean};
    return clean;
  } catch (e) {
    return null;
  }
}
