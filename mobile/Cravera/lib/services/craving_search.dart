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
/// runs a new search with the added text.
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
  SearchLocation? _near;
  List<Restaurant> _results = const [];
  int _index = 0;
  int _rejections = 0;
  PlacesSearchError? _error;

  /// Numbers each search. Only the newest may write its result, so a slow
  /// answer can't replace a newer search or reappear after a reset.
  int _request = 0;

  SearchStatus get status => _status;
  String get query => _query;
  PlacesSearchError? get error => _error;

  /// How many places the user has said No to in this search.
  int get rejections => _rejections;

  /// The place to show, while [status] is [SearchStatus.showing].
  Restaurant? get current => _status == SearchStatus.showing ? _results[_index] : null;

  /// True when the craving is longer than the server accepts.
  bool get queryTooLong => _query.length > maxQueryLength;

  /// True when the server found nothing at all (rather than the user
  /// rejecting every result).
  bool get foundNothing => _status == SearchStatus.exhausted && _results.isEmpty;

  /// Searches for [query] around [near]. Empty queries are ignored.
  Future<void> start(String query, SearchLocation near) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final request = ++_request;
    _query = trimmed;
    _near = near;
    _results = const [];
    _index = 0;
    _rejections = 0;
    _error = null;
    _searchedAt = null;
    if (trimmed.length > maxQueryLength) {
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
      final results = await service.search(query: trimmed, near: near);
      if (request != _request) return; // a newer search or a reset won
      _results = List.unmodifiable(results);
      _searchedAt = _now();
      _status = results.isEmpty ? SearchStatus.exhausted : SearchStatus.showing;
    } on PlacesSearchException catch (e) {
      if (request != _request) return;
      _error = e.error;
      _status = SearchStatus.failed;
    }
    notifyListeners();
  }

  /// "No": shows the next result from the same answer, without a request.
  void next() {
    if (!checkFresh() || _status != SearchStatus.showing) return;
    _rejections++;
    if (_index + 1 < _results.length) {
      _index++;
    } else {
      _status = SearchStatus.exhausted;
    }
    notifyListeners();
  }

  /// False (and [SearchStatus.expired]) when the results are older than
  /// [freshFor]. Call before showing or acting on a result.
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

  /// Runs a new search with [extra] added to the current craving.
  Future<void> refine(String extra) async {
    final near = _near;
    final added = extra.trim();
    if (near == null || added.isEmpty) return;
    await start('$_query $added', near);
  }

  /// Runs the same search again, for example after a network error.
  Future<void> retry() async {
    final near = _near;
    if (near == null || _query.isEmpty) return;
    await start(_query, near);
  }

  /// Back to no search. A search still in flight is dropped.
  void reset() {
    _request++;
    _status = SearchStatus.idle;
    _query = '';
    _near = null;
    _results = const [];
    _index = 0;
    _rejections = 0;
    _error = null;
    _searchedAt = null;
    notifyListeners();
  }

  void _fail(PlacesSearchError error) {
    _error = error;
    _status = SearchStatus.failed;
    notifyListeners();
  }
}
