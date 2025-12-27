// lib/services/places_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../secrets.dart';

/// Represents a place suggestion from Google Places Autocomplete
class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'] ?? {};
    return PlaceSuggestion(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: structured['main_text'] ?? json['description'] ?? '',
      secondaryText: structured['secondary_text'] ?? '',
    );
  }
}

/// Represents place details with coordinates
class PlaceDetails {
  final String placeId;
  final String name;
  final String formattedAddress;
  final double lat;
  final double lon;
  final String? locality;
  final String? country;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.lat,
    required this.lon,
    this.locality,
    this.country,
  });
}

class PlacesService {
  static const String _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';

  // Cache for place details to avoid repeated API calls
  static final Map<String, PlaceDetails> _detailsCache = {};

  /// Get place suggestions for autocomplete
  static Future<List<PlaceSuggestion>> getAutocompleteSuggestions(
    String input, {
    String? sessionToken,
  }) async {
    if (input.trim().isEmpty) return [];

    try {
      final params = {
        'input': input,
        'key': googleMapsApiKey,
        'types': '(cities)', // Focus on cities for weather app
      };

      if (sessionToken != null) {
        params['sessiontoken'] = sessionToken;
      }

      final url = Uri.parse(_autocompleteUrl).replace(queryParameters: params);
      final response = await http.get(url).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List<dynamic>;
          return predictions.map((p) => PlaceSuggestion.fromJson(p)).toList();
        }
      }
    } catch (e) {
      debugPrint('Places autocomplete error: $e');
    }

    return [];
  }

  /// Get full place suggestions including addresses and landmarks
  static Future<List<PlaceSuggestion>> getFullAutocompleteSuggestions(
    String input, {
    String? sessionToken,
  }) async {
    if (input.trim().isEmpty) return [];

    try {
      final params = {
        'input': input,
        'key': googleMapsApiKey,
        // No type restriction - get all types of places
      };

      if (sessionToken != null) {
        params['sessiontoken'] = sessionToken;
      }

      final url = Uri.parse(_autocompleteUrl).replace(queryParameters: params);
      final response = await http.get(url).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List<dynamic>;
          return predictions.map((p) => PlaceSuggestion.fromJson(p)).toList();
        }
      }
    } catch (e) {
      debugPrint('Places autocomplete error: $e');
    }

    return [];
  }

  /// Get place details including coordinates
  static Future<PlaceDetails?> getPlaceDetails(
    String placeId, {
    String? sessionToken,
  }) async {
    // Return cached result if available
    if (_detailsCache.containsKey(placeId)) {
      return _detailsCache[placeId];
    }

    try {
      final params = {
        'place_id': placeId,
        'key': googleMapsApiKey,
        'fields': 'place_id,name,formatted_address,geometry,address_components',
      };

      if (sessionToken != null) {
        params['sessiontoken'] = sessionToken;
      }

      final url = Uri.parse(_detailsUrl).replace(queryParameters: params);
      final response = await http.get(url).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'];
          final geometry = result['geometry'];
          final location = geometry?['location'];

          if (location != null) {
            String? locality;
            String? country;

            // Parse address components
            final components = result['address_components'] as List<dynamic>?;
            if (components != null) {
              for (final component in components) {
                final types = List<String>.from(component['types'] ?? []);
                if (types.contains('locality')) {
                  locality = component['long_name'];
                }
                if (types.contains('country')) {
                  country = component['long_name'];
                }
              }
            }

            final details = PlaceDetails(
              placeId: placeId,
              name: result['name'] ?? '',
              formattedAddress: result['formatted_address'] ?? '',
              lat: (location['lat'] as num).toDouble(),
              lon: (location['lng'] as num).toDouble(),
              locality: locality,
              country: country,
            );

            _detailsCache[placeId] = details;
            return details;
          }
        }
      }
    } catch (e) {
      debugPrint('Places details error: $e');
    }

    return null;
  }

  /// Generate a session token for autocomplete billing optimization
  static String generateSessionToken() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// Clear the details cache
  static void clearCache() {
    _detailsCache.clear();
  }
}

