import 'dart:async' show TimeoutException;
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/restaurant.dart';
import 'location_service.dart';

/// What went wrong with a search, so the screen can say something useful.
enum PlacesSearchError {
  /// The app has no Supabase URL or key, or the server rejected the key.
  notConfigured,

  /// No connection, or no answer in time.
  network,

  /// The search function or Google failed.
  server,

  /// The server refused the request as invalid (a bug on our side).
  rejected,
}

class PlacesSearchException implements Exception {
  final PlacesSearchError error;
  const PlacesSearchException(this.error);

  @override
  String toString() => 'PlacesSearchException($error)';
}

/// Searches for open restaurants through the `places-search` Edge Function.
///
/// The app never talks to Google directly: the function holds the Places key
/// and returns only places that are open now and inside the radius. Every
/// field shown comes from that response; nothing is filled in here.
class PlacesService {
  PlacesService({
    required this.publishableKey,
    http.Client? client,
    this.timeout = defaultTimeout,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// The request carries the user's exact location, so it only ever goes to
  /// Cravera's own project over HTTPS. The address is fixed in code
  /// ([AppConstants.supabaseUrl]), not read from `.env`, and Dart doesn't
  /// follow redirects for POST.
  static final endpoint = Uri.parse('${AppConstants.supabaseUrl}/functions/v1/places-search');

  /// Reads `SUPABASE_PUBLISHABLE_KEY` from `.env`. Returns null when it is
  /// missing, so callers can show [PlacesSearchError.notConfigured].
  static PlacesService? fromEnv({http.Client? client}) {
    String? key;
    try {
      key = dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY');
    } catch (_) {
      return null; // `.env` was never loaded.
    }
    if (key == null || key.trim().isEmpty) return null;
    return PlacesService(publishableKey: key.trim(), client: client);
  }

  final String publishableKey;
  final http.Client _client;
  final bool _ownsClient;

  /// Closes the HTTP client this service created. A client passed in stays
  /// open: whoever created it closes it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Longer than the function's own 8 s limit on its Google call.
  static const defaultTimeout = Duration(seconds: 12);
  final Duration timeout;

  /// Returns open restaurants for [query] around [near], best match first.
  /// An empty list means nothing matched. Throws [PlacesSearchException].
  Future<List<Restaurant>> search({required String query, required SearchLocation near, int? radiusMeters}) async {
    // Never follow a redirect: it could replay the location to another server.
    // A 3xx answer is treated as a server failure below. (Browsers ignore
    // this setting; web is not a v0.1.0 target.)
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll({'Content-Type': 'application/json', 'apikey': publishableKey})
      ..body = jsonEncode({
        'query': query,
        'latitude': near.latitude,
        'longitude': near.longitude,
        'radiusMeters': ?radiusMeters,
      });
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw const PlacesSearchException(PlacesSearchError.network);
    } on http.ClientException {
      throw const PlacesSearchException(PlacesSearchError.network);
    }

    switch (response.statusCode) {
      case 200:
        final String body;
        try {
          body = utf8.decode(response.bodyBytes);
        } on FormatException {
          throw const PlacesSearchException(PlacesSearchError.server);
        }
        return parseResults(body);
      case 400:
        throw const PlacesSearchException(PlacesSearchError.rejected);
      case 401:
      case 403:
        throw const PlacesSearchException(PlacesSearchError.notConfigured);
      default:
        throw const PlacesSearchException(PlacesSearchError.server);
    }
  }

  /// Parses the function's `{"results": [...]}` body. Entries without an ID,
  /// name or location are skipped rather than shown half-empty.
  static List<Restaurant> parseResults(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const PlacesSearchException(PlacesSearchError.server);
    }
    final results = decoded is Map<String, dynamic> ? decoded['results'] : null;
    if (results is! List) throw const PlacesSearchException(PlacesSearchError.server);

    final restaurants = <Restaurant>[];
    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final placeId = _string(item['placeId']);
      final name = _string(item['name']);
      final latitude = _double(item['latitude']);
      final longitude = _double(item['longitude']);
      if (placeId == null || name == null || latitude == null || longitude == null) continue;
      if (latitude.abs() > 90 || longitude.abs() > 180) continue;
      restaurants.add(Restaurant(
        placeId: placeId,
        name: name,
        address: _string(item['address']),
        cuisine: _string(item['cuisine']),
        priceLevel: _int(item['priceLevel']),
        rating: _double(item['rating']),
        distanceMeters: _int(item['distanceMeters']),
        photoName: _string(item['photoName']),
        latitude: latitude,
        longitude: longitude,
      ));
    }
    // Rows that all fail mean the response changed shape: that is a server
    // problem, not "nothing matched".
    if (results.isNotEmpty && restaurants.isEmpty) throw const PlacesSearchException(PlacesSearchError.server);
    return restaurants;
  }

  static String? _string(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
  static double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
  static int? _int(Object? v) => v is num && v.isFinite ? v.round() : null;
}
