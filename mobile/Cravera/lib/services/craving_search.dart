import 'package:flutter/foundation.dart';

import '../models/place_details.dart';
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
      if (request != _request) return;
      if (bytes == null) {
        // The gallery shares this download: its first page offers Try again.
        _galleryFailed.add(name);
        notifyListeners();
        return;
      }
      _photos[place.placeId] = bytes;
      notifyListeners();
      _loadAvatars(place, service, request);
    });
  }

  /// Fetches the avatars of the photo's authors, once the photo is shown
  /// (their credit only appears with it).
  void _loadAvatars(Restaurant place, PlacesService service, int request) =>
      _loadAvatarsOf(place.photoAuthors, service, request);

  void _loadAvatarsOf(List<PhotoAuthor> authors, PlacesService service, int request) {
    for (final author in authors) {
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

  /// Details for places the guest opened, by place ID (TASK-UI-4). Loaded
  /// only on open, never during search, so the pricier Places fields are
  /// paid for only when someone wants them.
  final Map<String, DetailsLoad> _details = {};

  /// The details of [current], or null if the guest hasn't opened it.
  DetailsLoad? get currentDetails {
    final place = current;
    return place == null ? null : _details[place.placeId];
  }

  /// Opens [current]'s details: loads them once, or again after a failure
  /// (Try again). A late answer from an older search is dropped.
  void openDetails() {
    final service = places;
    final place = current;
    if (place == null || service == null) return;
    final id = place.placeId;
    final existing = _details[id];
    if (existing != null && existing.status != DetailsStatus.failed) return;
    _details[id] = const DetailsLoad(DetailsStatus.loading);
    notifyListeners();
    final request = _request;
    service.details(id).then((details) {
      if (request != _request) return;
      _details[id] = details == null ? const DetailsLoad(DetailsStatus.failed) : DetailsLoad(DetailsStatus.loaded, details);
      notifyListeners();
    });
  }

  /// Gallery photo bytes by photo name (TASK-UI-4), for the opened card.
  /// A key with a null value means "asked, nothing (yet)".
  final Map<String, Uint8List?> _gallery = {};

  /// The gallery photo [name], once loaded. The first gallery photo is
  /// usually the search photo, which is reused rather than fetched again.
  Uint8List? galleryPhoto(String name) {
    final place = current;
    if (place != null && place.photoName == name && _photos[place.placeId] != null) return _photos[place.placeId];
    return _gallery[name];
  }

  /// Fetches one gallery photo, when the guest swipes to it (never ahead),
  /// and its authors' avatars. Never notifies synchronously, so a screen
  /// may call it while building. A late answer from an older search is dropped.
  ///
  /// A failed photo is not asked for again on rebuilds, only when the guest
  /// taps Try again ([retry]).
  void loadGalleryPhoto(DetailPhoto photo, {bool retry = false}) {
    final service = places;
    if (service == null || current == null) return;
    if (galleryPhoto(photo.name) != null) {
      _loadAvatarsOf(photo.authors, service, _request);
      return;
    }
    // The search photo's own download is still on its way: share it rather
    // than starting a second one that could finish differently.
    final place = current!;
    if (place.photoName == photo.name && _photos.containsKey(place.placeId) && !_galleryFailed.contains(photo.name)) {
      return;
    }
    if (_galleryFailed.contains(photo.name)) {
      if (!retry) return;
      _galleryFailed.remove(photo.name);
      notifyListeners();
    }
    if (_gallery.containsKey(photo.name)) return; // already on its way
    _gallery[photo.name] = null;
    final request = _request;
    service.photoBytes(photo.name).then((bytes) {
      if (request != _request) return;
      if (bytes == null) {
        _gallery.remove(photo.name);
        _galleryFailed.add(photo.name);
        notifyListeners();
        return;
      }
      _gallery[photo.name] = bytes;
      notifyListeners();
      _loadAvatarsOf(photo.authors, service, request);
    });
  }

  /// Gallery photos whose download failed in this search.
  final Set<String> _galleryFailed = {};

  /// True when the gallery photo [name] failed to load (show Try again).
  bool galleryFailed(String name) => _galleryFailed.contains(name) && galleryPhoto(name) == null;

  /// The opened card's gallery: the search photo first whenever the pick
  /// has one (so opening the card never loses a photo that already shows),
  /// then the other details photos, no more photos than the details sent
  /// (at most 5). The order depends only on the names, never on what has
  /// loaded, so pages don't move while the guest swipes.
  List<DetailPhoto> get currentGallery {
    final place = current;
    final photos = currentDetails?.details?.photos ?? const <DetailPhoto>[];
    if (place == null || photos.isEmpty) return const [];
    final name = place.photoName;
    if (name == null) return photos;
    final same = photos.where((p) => p.name == name);
    final first = same.isNotEmpty
        ? same.first
        : DetailPhoto(name: name, authors: place.photoCredits, mapsUri: place.photoMapsUri);
    return [first, ...photos.where((p) => p.name != name)].take(photos.length).toList();
  }

  /// The gallery photo [name] arrived but can't be shown (not a readable
  /// image): forget its bytes and offer Try again, like a failed download.
  void galleryPhotoBroken(String name) {
    if (_galleryFailed.contains(name)) return;
    _gallery.remove(name);
    final place = current;
    if (place != null && place.photoName == name) _photos[place.placeId] = null;
    _galleryFailed.add(name);
    notifyListeners();
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

  /// The signed-in person's default search distance (from their profile), or
  /// null for the server's default. Read when each search or refine is sent.
  int? radiusMeters;

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
    _details.clear();
    _gallery.clear();
    _galleryFailed.clear();
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
        radiusMeters: radiusMeters,
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
    _details.clear();
    _gallery.clear();
    _galleryFailed.clear();
    notifyListeners();
  }

  void _fail(PlacesSearchError error) {
    _error = error;
    _status = SearchStatus.failed;
    notifyListeners();
  }
}

enum DetailsStatus { loading, loaded, failed }

/// Where loading one place's details stands.
class DetailsLoad {
  final DetailsStatus status;

  /// Set when [status] is [DetailsStatus.loaded].
  final PlaceDetails? details;
  const DetailsLoad(this.status, [this.details]);
}
