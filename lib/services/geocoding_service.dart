// lib/services/geocoding_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../secrets.dart';

class GeocodingResult {
  final String streetAddress;
  final String? locality;
  final String? subLocality;
  final String? city;
  final String? district;
  final String? province;
  final String? country;
  final String formattedAddress;

  GeocodingResult({
    required this.streetAddress,
    this.locality,
    this.subLocality,
    this.city,
    this.district,
    this.province,
    this.country,
    required this.formattedAddress,
  });

  /// Returns a short display string for UI (street + area)
  String get shortAddress {
    final parts = <String>[];
    if (streetAddress.isNotEmpty && streetAddress != 'Unknown') {
      parts.add(streetAddress);
    }
    if (subLocality != null && subLocality!.isNotEmpty) {
      parts.add(subLocality!);
    } else if (locality != null && locality!.isNotEmpty) {
      parts.add(locality!);
    }
    return parts.isEmpty ? formattedAddress : parts.join(', ');
  }
}

class GeocodingService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  // Cache to avoid repeated API calls for same coordinates
  static final Map<String, GeocodingResult> _cache = {};

  /// Reverse geocode coordinates to get street address
  static Future<GeocodingResult?> reverseGeocode(double lat, double lon) async {
    // Round to 4 decimal places for cache key (approx 11m precision)
    final cacheKey = '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

    // Return cached result if available
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final url = Uri.parse(
          '$_baseUrl?latlng=$lat,$lon&key=$googleMapsApiKey&language=en');

      final response = await http.get(url).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = _parseGeocodingResponse(data['results']);
          _cache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      // Silently fail - geocoding is optional
      print('Geocoding error: $e');
    }

    return null;
  }

  static GeocodingResult _parseGeocodingResponse(List<dynamic> results) {
    String streetAddress = '';
    String? locality;
    String? subLocality;
    String? city;
    String? district;
    String? province;
    String? country;
    String formattedAddress = results.first['formatted_address'] ?? '';

    // Parse address components from the most detailed result
    for (final result in results) {
      final components = result['address_components'] as List<dynamic>;

      for (final component in components) {
        final types = List<String>.from(component['types'] ?? []);
        final longName = component['long_name'] ?? '';

        // Street number + route = street address
        if (types.contains('street_number')) {
          streetAddress = longName;
        }
        if (types.contains('route')) {
          streetAddress =
              streetAddress.isEmpty ? longName : '$streetAddress $longName';
        }
        if (types.contains('sublocality_level_1') ||
            types.contains('sublocality')) {
          subLocality ??= longName;
        }
        if (types.contains('locality')) {
          locality ??= longName;
        }
        if (types.contains('administrative_area_level_2')) {
          city ??= longName;
          district ??= longName;
        }
        if (types.contains('administrative_area_level_1')) {
          province ??= longName;
        }
        if (types.contains('country')) {
          country ??= longName;
        }
      }
    }

    // If no street address found, try to get a meaningful location name
    if (streetAddress.isEmpty) {
      // Try premise, establishment, or point_of_interest
      for (final result in results) {
        final components = result['address_components'] as List<dynamic>;
        for (final component in components) {
          final types = List<String>.from(component['types'] ?? []);
          if (types.contains('premise') ||
              types.contains('establishment') ||
              types.contains('point_of_interest') ||
              types.contains('neighborhood')) {
            streetAddress = component['long_name'] ?? '';
            if (streetAddress.isNotEmpty) break;
          }
        }
        if (streetAddress.isNotEmpty) break;
      }
    }

    return GeocodingResult(
      streetAddress: streetAddress.isEmpty ? 'Unknown' : streetAddress,
      locality: locality,
      subLocality: subLocality,
      city: city,
      district: district,
      province: province,
      country: country,
      formattedAddress: formattedAddress,
    );
  }

  /// Clear the cache (useful when memory is low)
  static void clearCache() {
    _cache.clear();
  }
}
