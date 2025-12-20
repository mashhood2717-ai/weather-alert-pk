// lib/services/location_service.dart

import 'package:geolocator/geolocator.dart';

Future<Position> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return Future.error('Location permissions are permanently denied.');
  }

  // FAST LOCATION STRATEGY:
  // 1. Try last known position first (instant, no GPS wait)
  // 2. If no cached position, get current with timeout

  Position? lastKnown;
  try {
    lastKnown = await Geolocator.getLastKnownPosition();
  } catch (_) {
    // Ignore - will fall back to getCurrentPosition
  }

  // If we have a recent last known position (< 5 minutes old), use it immediately
  if (lastKnown != null) {
    final age = DateTime.now().difference(lastKnown.timestamp);
    if (age.inMinutes < 5) {
      // Use cached position for instant response
      return lastKnown;
    }
  }

  // Get fresh position with 10-second timeout
  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low, // Faster than medium
      timeLimit: const Duration(seconds: 10),
    );
  } catch (e) {
    // If timeout and we have any last known position, use it as fallback
    if (lastKnown != null) {
      return lastKnown;
    }
    rethrow;
  }
}
