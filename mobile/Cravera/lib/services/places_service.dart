import 'dart:async' show Completer, StreamSubscription, TimeoutException, unawaited;
import 'dart:typed_data' show BytesBuilder, Uint8List;
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

/// One answer from `places-search`: the places, best fit first, and the
/// search intent the server used.
class SearchAnswer {
  final List<Restaurant> results;

  /// The server's reading of the craving. The app doesn't interpret it: it
  /// only sends it back as `previousIntent` when the user refines, and the
  /// server validates it again. Null when the server sent none.
  final Map<String, Object?>? intent;

  const SearchAnswer(this.results, {this.intent});
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

  /// The function that turns a photo name into an image link without the key.
  static final photoEndpoint = Uri.parse('${AppConstants.supabaseUrl}/functions/v1/place-photo');

  /// Only Places photo names are sent, matching what the function accepts.
  static final _photoName = RegExp(r'^places/[A-Za-z0-9_-]{1,300}/photos/[A-Za-z0-9_-]{1,1000}$');

  /// An image link for [photoName], or null if there isn't one. A photo is
  /// optional, so every failure is just "no photo", never an error.
  Future<String?> photoUrl(String photoName) async {
    if (!_photoName.hasMatch(photoName)) return null;
    final request = http.Request('POST', photoEndpoint)
      ..followRedirects = false
      ..headers.addAll({'Content-Type': 'application/json', 'apikey': publishableKey})
      ..body = jsonEncode({'photoName': photoName});
    try {
      final response = await _client.send(request).then(http.Response.fromStream).timeout(timeout);
      if (response.statusCode != 200) return null;
      final uri = (jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>)['photoUri'];
      return uri is String && isSafePhotoUri(uri) ? uri : null;
    } catch (_) {
      return null;
    }
  }

  /// Largest photo we accept; Google's 800 px photos are far smaller.
  static const maxPhotoBytes = 5 * 1024 * 1024;

  /// The photo for [photoName] as image bytes, or null. The app downloads it
  /// itself, without following redirects, so the request can never leave
  /// Google's photo host (Flutter's own image loader would follow them).
  Future<Uint8List?> photoBytes(String photoName) async {
    final link = await photoUrl(photoName);
    if (link == null) return null;
    final request = http.Request('GET', Uri.parse(link))..followRedirects = false;
    StreamSubscription<List<int>>? reading;
    try {
      final response = await _client.send(request).timeout(timeout);
      // Decide from the headers before reading any of the body.
      final type = response.headers['content-type'] ?? '';
      final declared = response.contentLength;
      if (response.statusCode != 200 || !type.startsWith('image/') || (declared != null && declared > maxPhotoBytes)) {
        unawaited(response.stream.listen(null).cancel());
        return null;
      }
      // Read chunk by chunk and stop as soon as the limit is passed, so a
      // large or endless answer never fills memory.
      final bytes = BytesBuilder(copy: false);
      final done = Completer<Uint8List?>();
      reading = response.stream.listen(
        (chunk) {
          bytes.add(chunk);
          if (bytes.length > maxPhotoBytes && !done.isCompleted) done.complete(null);
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete(null);
        },
        onDone: () {
          if (!done.isCompleted) done.complete(bytes.isEmpty ? null : bytes.takeBytes());
        },
        cancelOnError: true,
      );
      return await done.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      await reading?.cancel(); // stops a download that passed the limit or timed out
    }
  }

  /// Images load only from Google's photo host over HTTPS.
  static bool isSafePhotoUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'googleusercontent.com' || uri.host.endsWith('.googleusercontent.com'));
  }

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
  /// Empty results mean nothing matched. When refining, [previousIntent] is
  /// the intent of the search being refined. [localHour] (0-23) lets the
  /// server read "late-night" or "breakfast". Throws [PlacesSearchException].
  Future<SearchAnswer> search({
    required String query,
    required SearchLocation near,
    int? radiusMeters,
    Map<String, Object?>? previousIntent,
    int? localHour,
  }) async {
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
        'previousIntent': ?previousIntent,
        'localHour': ?localHour,
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
        return SearchAnswer(parseResults(body), intent: parseIntent(body));
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
        photoAuthor: _string(item['photoAuthor']),
        photoAuthorUri: _httpsUrl(item['photoAuthorUri']),
        latitude: latitude,
        longitude: longitude,
        matches: _matches(item['matches']),
      ));
    }
    // Rows that all fail mean the response changed shape: that is a server
    // problem, not "nothing matched".
    if (results.isNotEmpty && restaurants.isEmpty) throw const PlacesSearchException(PlacesSearchError.server);
    return restaurants;
  }

  /// The `intent` object of a response body, or null.
  static Map<String, Object?>? parseIntent(String body) {
    try {
      final decoded = jsonDecode(body);
      final intent = decoded is Map<String, dynamic> ? decoded['intent'] : null;
      return intent is Map<String, dynamic> ? Map.unmodifiable(intent) : null;
    } on FormatException {
      return null;
    }
  }

  /// The intent's phrases this place matches, as the server sent them. Only
  /// short plain strings are kept; anything else is dropped.
  static List<String> _matches(Object? v) => v is List
      ? List.unmodifiable(v.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty && s.length <= 30).take(4))
      : const [];

  static String? _httpsUrl(Object? v) {
    final s = _string(v);
    final uri = s == null ? null : Uri.tryParse(s);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? s : null;
  }

  static String? _string(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
  static double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
  static int? _int(Object? v) => v is num && v.isFinite ? v.round() : null;
}
