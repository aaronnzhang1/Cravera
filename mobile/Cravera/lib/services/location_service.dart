import 'dart:async' show TimeoutException;

import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

/// A point to search around, plus a short label to show the user.
class SearchLocation {
  final double latitude;
  final double longitude;
  final String label;

  const SearchLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
  });
}

/// Why the device location could not be used.
enum LocationProblem { serviceOff, denied, deniedForever, failed }

/// Either a location or the reason there isn't one.
class LocationResult {
  final SearchLocation? location;
  final LocationProblem? problem;

  const LocationResult.found(SearchLocation this.location) : problem = null;
  const LocationResult.failed(LocationProblem this.problem) : location = null;
}

/// Finds where to search: the device location, or a place the user typed.
///
/// Screens depend on this class, not on geolocator or geocoding directly,
/// so tests can pass a fake subclass.
class LocationService {
  const LocationService();

  /// The oldest and least accurate last-known fix we still call "Near you".
  /// Older or vaguer fixes could be from somewhere the user has left.
  static const maxCachedAge = Duration(minutes: 10);
  static const maxCachedAccuracyMeters = 1000.0;

  /// Whether a last-known fix is recent and precise enough to search around.
  static bool cachedFixIsUsable({required DateTime takenAt, required double accuracyMeters, required DateTime now}) =>
      now.difference(takenAt) <= maxCachedAge && accuracyMeters <= maxCachedAccuracyMeters;

  /// Asks for permission if needed, then reads the device location.
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(LocationProblem.serviceOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(LocationProblem.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return const LocationResult.failed(LocationProblem.denied);
      }
      // A single high-accuracy request uses GPS, which works even where there
      // is no network-based location (such as the Android emulator).
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } on TimeoutException {
        // No fresh fix in time (for example indoors): use the last one the
        // phone knows, but only if it is recent and precise. Otherwise the
        // user is asked to type a place. Any other error (permission revoked,
        // location turned off) skips the cache and falls through to `failed`.
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null &&
            cachedFixIsUsable(takenAt: cached.timestamp, accuracyMeters: cached.accuracy, now: DateTime.now())) {
          position = cached;
        }
      }
      if (position == null) {
        return const LocationResult.failed(LocationProblem.failed);
      }
      return LocationResult.found(SearchLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        label: 'Near you',
      ));
    } catch (_) {
      return const LocationResult.failed(LocationProblem.failed);
    }
  }

  /// Turns a typed place or address into coordinates, or null if not found.
  /// Uses the phone's built-in geocoder, so it needs no API key.
  Future<SearchLocation?> lookUp(String place) async {
    final query = place.trim();
    if (query.isEmpty) return null;
    try {
      final matches = await geocoding.Geocoding().locationFromAddress(query);
      if (matches.isEmpty) return null;
      return SearchLocation(
        latitude: matches.first.latitude,
        longitude: matches.first.longitude,
        label: query,
      );
    } catch (_) {
      return null;
    }
  }
}
