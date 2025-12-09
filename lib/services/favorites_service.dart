// lib/services/favorites_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteLocation {
  final String name;
  final double lat;
  final double lon;
  final String? icao; // For METAR-enabled locations
  final DateTime addedAt;

  FavoriteLocation({
    required this.name,
    required this.lat,
    required this.lon,
    this.icao,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lon': lon,
        'icao': icao,
        'addedAt': addedAt.toIso8601String(),
      };

  factory FavoriteLocation.fromJson(Map<String, dynamic> json) {
    return FavoriteLocation(
      name: json['name'] ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      icao: json['icao'],
      addedAt: json['addedAt'] != null
          ? DateTime.parse(json['addedAt'])
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavoriteLocation &&
        other.name.toLowerCase() == name.toLowerCase();
  }

  @override
  int get hashCode => name.toLowerCase().hashCode;
}

class FavoritesService {
  static const String _favoritesKey = 'favorite_locations';
  static const int _maxFavorites = 10;

  // Singleton
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  /// Get all favorites
  Future<List<FavoriteLocation>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? favoritesJson = prefs.getString(_favoritesKey);

    if (favoritesJson == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(favoritesJson);
      return decoded.map((e) => FavoriteLocation.fromJson(e)).toList();
    } catch (e) {
      print('Error parsing favorites: $e');
      return [];
    }
  }

  /// Add a favorite location
  Future<bool> addFavorite(FavoriteLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await getFavorites();

    // Check if already exists
    if (favorites
        .any((f) => f.name.toLowerCase() == location.name.toLowerCase())) {
      return false; // Already exists
    }

    // Check max limit
    if (favorites.length >= _maxFavorites) {
      // Remove oldest
      favorites.sort((a, b) => a.addedAt.compareTo(b.addedAt));
      favorites.removeAt(0);
    }

    favorites.add(location);

    final encoded = jsonEncode(favorites.map((e) => e.toJson()).toList());
    await prefs.setString(_favoritesKey, encoded);
    return true;
  }

  /// Remove a favorite by name
  Future<void> removeFavorite(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await getFavorites();

    favorites.removeWhere((f) => f.name.toLowerCase() == name.toLowerCase());

    final encoded = jsonEncode(favorites.map((e) => e.toJson()).toList());
    await prefs.setString(_favoritesKey, encoded);
  }

  /// Check if a location is favorite
  Future<bool> isFavorite(String name) async {
    final favorites = await getFavorites();
    return favorites.any((f) => f.name.toLowerCase() == name.toLowerCase());
  }

  /// Toggle favorite status
  Future<bool> toggleFavorite(FavoriteLocation location) async {
    final isFav = await isFavorite(location.name);
    if (isFav) {
      await removeFavorite(location.name);
      return false;
    } else {
      await addFavorite(location);
      return true;
    }
  }

  /// Clear all favorites
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_favoritesKey);
  }
}
