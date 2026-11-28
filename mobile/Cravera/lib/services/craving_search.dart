import 'package:flutter/foundation.dart';

import '../models/restaurant.dart';
import 'location_service.dart';
import 'places_service.dart';

/// Where a craving search is: nothing yet, asking the server, showing one
/// place, out of places, failed, or too old to trust (places may have closed).
enum SearchStatus { idle, loading, showing, exhausted, failed, expired }

/// One craving search and the user's way through its results.
///
/// A search asks the server once. "No" moves to the next result from the
/// same answer without a new request. When the results run out the status is
/// [SearchStatus.exhausted] and the screen asks the user to refine, which
/// runs a new search that changes the previous one (the server gets the added
/// text and the previous search's intent).
class CravingSearch extends ChangeNotifier {
  CravingSearch({this.places, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// The server refuses longer cravings, so they are stopped before sending.
  static const maxQueryLength = 200;

  /// "Open now" was true when we searched. After this long, places may have
  /// closed, so the results are dropped and the user searches again.
  static const freshFor = Duration(minutes: 15);

  final DateTime Function() _now;
  DateTime? _searchedAt;

  /// Null when the app has no publishable key: every search then fails with
  /// [PlacesSearchError.notConfigured].
  final PlacesService? places;

  SearchStatus _status = SearchStatus.idle;
  String _query = '';

  /// What the guest typed, one entry per message: the craving, then each
  /// refine. The chat shows each as its own bubble.
  List<String> _messages = const [];
  SearchLocation? _near;

  /// What was actually sent, so [retry] repeats it exactly. When refining,
  /// [_sentQuery] is only the added text and [_sentIntent] the previous intent.
  String _sentQuery = '';
  Map<String, Object?>? _sentIntent;

  /// The intent of the current answer, sent back when the user refines.
  Map<String, Object?>? _intent;
  List<Restaurant> _results = const [];
  int _index = 0;
  int _rejections = 0;

  /// Place IDs shown in this search session (the first craving and every
  /// refine of it), oldest first. A refine sends them so the server leaves
  /// them out, and they are filtered here too: a place the guest already saw
  /// (and said No to) never comes back in the same session (TASK-005).
  final List<String> _shown = [];

  /// Places the guest said No to in this session. Even a retry (after an
  /// error, or to refresh expired results) never brings these back.
  final List<String> _rejected = [];

  /// The most IDs sent with one request (the server accepts this many).
  static const maxExcluded = 100;

  void _markShown() {
    if (_status != SearchStatus.showing) return;
    final id = _results[_index].placeId;
    if (!_shown.contains(id)) _shown.add(id);
  }
  PlacesSearchError? _error;

  /// Numbers each search. Only the newest may write its result, so a slow
  /// answer can't replace a newer search or reappear after a reset.
  int _request = 0;

  SearchStatus get status => _status;

  /// Changes with every search (including refines and retries), so a screen
  /// can remember something for one search only.
  int get searchId => _request;
  String get query => _query;

  /// The guest's messages in this search, oldest first.
  List<String> get messages => _messages;
  PlacesSearchError? get error => _error;

  /// How many places the user has said No to in this search.
  int get rejections => _rejections;

  /// After this many Nos, the screen offers a small "Narrow it down" option.
  /// Earlier felt pushy (maintainer, 2026-11-26).
  static const offerRefineAfter = 5;

  /// Whether to offer narrowing the search, under the current card.
  bool get offerRefine => _status == SearchStatus.showing && _rejections >= offerRefineAfter;

  /// Photo bytes by place ID, fetched only for places actually shown. A key
  /// with a null value means "asked, no photo (yet)".
  final Map<String, Uint8List?> _photos = {};

  /// Avatar bytes by avatar link, for the authors of photos that loaded.
  final Map<String, Uint8List?> _avatars = {};

  /// The avatar at [avatarUri], once it has loaded; null shows an initial.
  Uint8List? avatar(String? avatarUri) => avatarUri == null ? null : _avatars[avatarUri];

  /// The place to show, while [status] is [SearchStatus.showing].
  Restaurant? get current => _status == SearchStatus.showing ? _results[_index] : null;

  /// The photo of [current], once it has loaded; null means show the placeholder.
  Uint8List? get currentPhoto {
    final place = current;
    return place == null ? null : _photos[place.placeId];
  }

  /// Fetches the photo for the first pick of a search only (maintainer,
  /// 2026-11-27: keep photos free), so No never makes a Google request.
  /// A late answer from an
  /// older search is dropped.
  void _loadPhoto() {
    final service = places;
    if (_status != SearchStatus.showing || service == null) return;
    final place = _results[_index];
    final name = place.photoName;
    if (name == null || _photos.containsKey(place.placeId)) return;
    _photos[place.placeId] = null;
    final request = _request;
    service.photoBytes(name).then((bytes) {
      if (request != _request || bytes == null) return;
      _photos[place.placeId] = bytes;
      notifyListeners();
      _loadAvatars(place, service, request);
    });
  }

  /// Fetches the avatars of the photo's authors, once the photo is shown
  /// (their credit only appears with it).
  void _loadAvatars(Restaurant place, PlacesService service, int request) {
    for (final author in place.photoAuthors) {
      final link = author.avatarUri;
      if (link == null || _avatars.containsKey(link)) continue;
      _avatars[link] = null;
      service.avatarBytes(link).then((bytes) {
        if (request != _request || bytes == null) return;
        _avatars[link] = bytes;
        notifyListeners();
      });
    }
  }

  /// True when the craving is longer than the server accepts.
  bool get queryTooLong => _sentQuery.length > maxQueryLength;

  /// True when the server found nothing at all (rather than the user
  /// rejecting every result).
  bool get foundNothing => _status == SearchStatus.exhausted && _results.isEmpty;

  /// True when the last answer had open matches, but the guest had already
  /// seen all of them in this session (TASK-005).
  bool get noNewPlaces => foundNothing && _noNewPlaces;
  bool _noNewPlaces = false;

  /// Searches for [query] around [near]. Empty queries are ignored.
  Future<void> start(String query, SearchLocation near) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _messages = List.unmodifiable([trimmed]);
    _shown.clear(); // a new craving starts a new session
    _rejected.clear();
    await _run(display: trimmed, send: trimmed, previous: null, near: near);
  }

  /// The place IDs the last request left out, so [retry] repeats it exactly
  /// (an expired search shows its places again; a refine still skips them).
  List<String> _sentExcluded = const [];

  /// Every place shown so far in this session. The request sends only the
  /// newest [maxExcluded]; the answer is filtered against all of them.
  List<String> get _excludeNow => List.unmodifiable(_shown);

  Future<void> _run({
    required String display,
    required String send,
    required Map<String, Object?>? previous,
    required SearchLocation near,
    List<String> exclude = const [],
  }) async {
    final request = ++_request;
    _sentExcluded = exclude;
    _query = display;
    _sentQuery = send;
    _sentIntent = previous;
    _intent = null;
    _near = near;
    _results = const [];
    _index = 0;
    _rejections = 0;
    _error = null;
    _searchedAt = null;
    _photos.clear(); // photo links are short-lived; each search starts fresh
    _avatars.clear();
    if (send.length > maxQueryLength) {
      // Retrying can't help: the user has to shorten it.
      _fail(PlacesSearchError.rejected);
      return;
    }
    _status = SearchStatus.loading;
    notifyListeners();

    final service = places;
    if (service == null) {
      _fail(PlacesSearchError.notConfigured);
      return;
    }
    try {
      final answer = await service.search(
        query: send,
        near: near,
        previousIntent: previous,
        localHour: _now().hour,
        excludePlaceIds: exclude.isEmpty
            ? null
            : (exclude.length > maxExcluded ? exclude.sublist(exclude.length - maxExcluded) : exclude),
      );
      if (request != _request) return; // a newer search or a reset won
      // Also here, not only on the server: never show a place twice.
      final results = [for (final r in answer.results) if (!exclude.contains(r.placeId)) r];
      _noNewPlaces = results.isEmpty && (answer.noNewPlaces || answer.results.isNotEmpty);
      _results = List.unmodifiable(results);
      _intent = answer.intent;
      _searchedAt = _now();
      _status = results.isEmpty ? SearchStatus.exhausted : SearchStatus.showing;
      _markShown();
    } on PlacesSearchException catch (e) {
      if (request != _request) return;
      _error = e.error;
      _status = SearchStatus.failed;
    }
    notifyListeners();
    _loadPhoto();
  }

  /// "No": shows the next result from the same answer, without a request.
  void next() {
    if (!checkFresh() || _status != SearchStatus.showing) return;
    _rejections++;
    final id = _results[_index].placeId;
    if (!_rejected.contains(id)) _rejected.add(id);
    if (_index + 1 < _results.length) {
      _index++;
      _markShown();
    } else {
      _status = SearchStatus.exhausted;
    }
    notifyListeners();
  }

  /// False (and [SearchStatus.expired]) when the results are older than
  /// [freshFor]. Call before showing or acting on a result.
  /// Whether the results are still within [freshFor]. Doesn't change state,
  /// so a screen can read it while building.
  bool get isFresh {
    final at = _searchedAt;
    return at == null || _now().difference(at) <= freshFor;
  }

  bool checkFresh() {
    final at = _searchedAt;
    if (at == null || _now().difference(at) <= freshFor) return true;
    if (_status == SearchStatus.showing || _status == SearchStatus.exhausted) {
      _status = SearchStatus.expired;
      _results = const [];
      notifyListeners();
    }
    return false;
  }

  /// Refines the current search with [extra] ("cheaper", "no seafood"). The
  /// server gets [extra] and the current intent, so it changes the search
  /// instead of restarting. Without an intent (the server sent none), the
  /// text is added to the craving as before.
  Future<void> refine(String extra) async {
    final near = _near;
    final added = extra.trim();
    if (near == null || added.isEmpty) return;
    final intent = _intent;
    _messages = List.unmodifiable([..._messages, added]);
    if (intent == null) {
      final combined = '$_query $added';
      await _run(display: combined, send: combined, previous: null, near: near, exclude: _excludeNow);
    } else {
      await _run(display: '$_query $added', send: added, previous: intent, near: near, exclude: _excludeNow);
    }
  }

  /// Runs the same search again, for example after a network error.
  Future<void> retry() async {
    final near = _near;
    if (near == null || _sentQuery.isEmpty) return;
    // The same request, but never a place said No to since it was sent.
    final exclude = [..._sentExcluded, for (final id in _rejected) if (!_sentExcluded.contains(id)) id];
    await _run(display: _query, send: _sentQuery, previous: _sentIntent, near: near, exclude: exclude);
  }

  /// Back to no search. A search still in flight is dropped.
  void reset() {
    _request++;
    _shown.clear();
    _rejected.clear();
    _status = SearchStatus.idle;
    _query = '';
    _messages = const [];
    _sentQuery = '';
    _sentIntent = null;
    _intent = null;
    _near = null;
    _results = const [];
    _index = 0;
    _rejections = 0;
    _error = null;
    _searchedAt = null;
    _photos.clear();
    _avatars.clear();
    notifyListeners();
  }

  void _fail(PlacesSearchError error) {
    _error = error;
    _status = SearchStatus.failed;
    notifyListeners();
  }
}
