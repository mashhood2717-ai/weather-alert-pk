// lib/services/geocoding_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  final String? extractedAreaName; // Intelligently extracted area name

  GeocodingResult({
    required this.streetAddress,
    this.locality,
    this.subLocality,
    this.city,
    this.district,
    this.province,
    this.country,
    required this.formattedAddress,
    this.extractedAreaName,
  });

  /// Returns the best available main location name
  /// Priority: locality > city > district > extractedAreaName > province
  String get mainLocationName {
    if (locality != null && locality!.isNotEmpty) return locality!;
    if (city != null && city!.isNotEmpty) return city!;
    if (district != null && district!.isNotEmpty) return district!;
    if (extractedAreaName != null && extractedAreaName!.isNotEmpty) {
      return extractedAreaName!;
    }
    if (province != null && province!.isNotEmpty) return province!;
    return 'Unknown';
  }

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
  /// Returns true if coordinates are within Islamabad bounding box
  static bool _isInIslamabad(double lat, double lon) {
    // Rough bounding box for Islamabad city
    // North: 33.85, South: 33.60, West: 72.80, East: 73.20
    return lat >= 33.60 && lat <= 33.85 && lon >= 72.80 && lon <= 73.20;
  }

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
          var result = _parseGeocodingResponse(data['results']);
          // Force city to Islamabad if inside bounding box
          if (_isInIslamabad(lat, lon)) {
            result = GeocodingResult(
              streetAddress: result.streetAddress,
              locality: result.locality,
              subLocality: result.subLocality,
              city: 'Islamabad',
              district: result.district,
              province: result.province,
              country: result.country,
              formattedAddress: result.formattedAddress,
              extractedAreaName: result.extractedAreaName,
            );
          }
          _cache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      // Silently fail - geocoding is optional
      debugPrint('Geocoding error: $e');
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
    String? extractedAreaName;

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
            types.contains('sublocality') ||
            types.contains('sublocality_level_2')) {
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
        // Also check for neighborhood and political areas
        if (types.contains('neighborhood') || types.contains('political')) {
          if (extractedAreaName == null && longName.isNotEmpty) {
            // Only use if it's not a generic name
            if (!_isGenericName(longName)) {
              extractedAreaName = longName;
            }
          }
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
              types.contains('neighborhood') ||
              types.contains('natural_feature') ||
              types.contains('colloquial_area')) {
            streetAddress = component['long_name'] ?? '';
            if (streetAddress.isNotEmpty) break;
          }
        }
        if (streetAddress.isNotEmpty) break;
      }
    }

    // If still no meaningful location, extract from formatted address intelligently
    if ((locality == null || locality.isEmpty) &&
        (city == null || city.isEmpty) &&
        formattedAddress.isNotEmpty) {
      extractedAreaName = _extractAreaFromFormattedAddress(
        formattedAddress,
        province,
        country,
      );
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
      extractedAreaName: extractedAreaName,
    );
  }

  /// Extract meaningful area name from formatted address
  /// For example: "M-2 Motorway, Rawalpindi District, Punjab, Pakistan"
  /// Should extract: "Rawalpindi District" or near major city
  static String? _extractAreaFromFormattedAddress(
    String formattedAddress,
    String? province,
    String? country,
  ) {
    // Split by comma and look for meaningful parts
    final parts = formattedAddress.split(',').map((p) => p.trim()).toList();

    // Remove country, province, and postal codes from consideration
    final meaningfulParts = parts.where((part) {
      if (part.isEmpty) return false;
      if (country != null && part.toLowerCase() == country.toLowerCase()) {
        return false;
      }
      if (province != null && part.toLowerCase() == province.toLowerCase()) {
        return false;
      }
      // Skip postal codes (numbers only or alphanumeric codes)
      if (RegExp(r'^[0-9\s-]+$').hasMatch(part)) return false;
      // Skip very short parts
      if (part.length < 3) return false;
      return true;
    }).toList();

    // Look for known Pakistani patterns
    for (final part in meaningfulParts) {
      // Check if it contains "District" - common in Pakistan addresses
      if (part.toLowerCase().contains('district')) {
        // Extract just the name before "District"
        final match =
            RegExp(r'(\w+)\s*District', caseSensitive: false).firstMatch(part);
        if (match != null) {
          return match.group(1)?.trim();
        }
        return part;
      }
      // Check for Tehsil
      if (part.toLowerCase().contains('tehsil')) {
        final match =
            RegExp(r'(\w+)\s*Tehsil', caseSensitive: false).firstMatch(part);
        if (match != null) {
          return match.group(1)?.trim();
        }
      }
    }

    // If we have meaningful parts, try the first one that looks like a place name
    // Skip motorway/highway names for main location
    for (final part in meaningfulParts) {
      if (_isMotorwayOrHighway(part)) continue;
      if (part.length > 2) {
        return part;
      }
    }

    // Last resort: return first meaningful part even if it's a motorway
    if (meaningfulParts.isNotEmpty) {
      return meaningfulParts.first;
    }

    return null;
  }

  /// Check if a name is a motorway or highway
  static bool _isMotorwayOrHighway(String name) {
    final lower = name.toLowerCase();
    return lower.contains('motorway') ||
        lower.contains('highway') ||
        lower.contains('expressway') ||
        lower.startsWith('m-') ||
        lower.startsWith('n-') ||
        RegExp(r'^[MN]\d+\b', caseSensitive: false).hasMatch(name);
  }

  /// Check if a name is too generic to be useful
  static bool _isGenericName(String name) {
    final lower = name.toLowerCase();
    return lower == 'pakistan' ||
        lower == 'punjab' ||
        lower == 'sindh' ||
        lower == 'kpk' ||
        lower == 'balochistan' ||
        lower == 'ict';
  }

  /// Clear the cache (useful when memory is low)
  static void clearCache() {
    _cache.clear();
  }
}

