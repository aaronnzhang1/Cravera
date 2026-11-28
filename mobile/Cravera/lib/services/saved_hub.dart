import 'dart:async';

import 'package:flutter/foundation.dart';

import 'places_service.dart';
import 'saved_places_service.dart';

enum SavedLoadStatus { idle, loading, loaded, failed }

/// Fresh basics for one saved place, from the `saved-places` function. Never
/// stored: fetched each time Saved opens (Google's terms).
class SavedBasics {
  const SavedBasics({required this.placeId, this.name, this.address, this.city, this.latitude, this.longitude, this.missing = false});

  final String placeId;
  final String? name;
  final String? address;
  final String? city;
  final double? latitude;
  final double? longitude;

  /// Google no longer knows this place (closed for good or removed).
  final bool missing;

  bool get failed => name == null;
}

/// The signed-in person's saved places (TASK-004): their rows, and the fresh
/// basics shown for them. Every call is bound to the account it started for:
/// an answer that arrives after a sign-out or account switch is dropped, so
/// one person's places never show for another.
class SavedHub extends ChangeNotifier {
  SavedHub({this.service, this.places, this.accessToken, this.writeTimeout = const Duration(seconds: 10)});

  /// How long a change waits for the server before it counts as a lost answer.
  final Duration writeTimeout;

  /// Null when the app has no Supabase key; tests pass a fake.
  final SavedPlacesService? service;
  final PlacesService? places;

  /// The signed-in person's current access token, for the `saved-places`
  /// function (it reads their own rows with it).
  final String? Function()? accessToken;

  /// Counts confirmed or possibly-applied changes, so a list read that started
  /// before one can't overwrite it when it answers later.
  int _changes = 0;

  String? _account;
  int _generation = 0;

  SavedLoadStatus _status = SavedLoadStatus.idle;
  SavedLoadStatus get status => _status;

  List<SavedPlace> _items = const [];

  /// Saved places, newest first.
  List<SavedPlace> get items => _items;

  List<SavedPlace> byStatus(SavedStatus s) => [for (final p in _items) if (p.status == s) p];

  bool contains(String placeId) => _items.any((p) => p.placeId == placeId);

  final Map<String, SavedBasics> _basics = {};
  SavedBasics? basics(String placeId) => _basics[placeId];

  SavedLoadStatus _basicsStatus = SavedLoadStatus.idle;
  SavedLoadStatus get basicsStatus => _basicsStatus;

  /// The most places the list fetches basics for (the function's limit).
  static const maxPlaces = 50;

  /// Follows the signed-in account: clears everything of the previous one and
  /// loads the new one's places. Null for guests and signed out.
  void switchAccount(String? accountId) {
    if (accountId == _account) return;
    _account = accountId;
    _generation++;
    _items = const [];
    _basics.clear();
    _status = SavedLoadStatus.idle;
    _basicsStatus = SavedLoadStatus.idle;
    notifyListeners();
    if (accountId != null) unawaited(load());
  }

  bool _current(int generation, String? account) => generation == _generation && account == _account;

  /// Loads the person's saved places (again after a failure).
  Future<void> load() async {
    final s = service;
    final account = _account;
    if (s == null || account == null) return;
    final generation = _generation;
    final changesBefore = _changes;
    if (_status != SavedLoadStatus.loaded) _status = SavedLoadStatus.loading;
    notifyListeners();
    final list = await s.list().timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (!_current(generation, account)) return;
    if (list != null && _changes != changesBefore) {
      // A change landed while this read was on its way: it may not include
      // it. Read again rather than show an older snapshot.
      return load();
    }
    if (list == null) {
      // Keep what is known; before the first load nothing can be toggled.
      if (_status != SavedLoadStatus.loaded) _status = SavedLoadStatus.failed;
    } else {
      _items = list;
      _status = SavedLoadStatus.loaded;
    }
    notifyListeners();
  }

  /// Fetches fresh basics for the saved places (when Saved opens): one
  /// request for at most [maxPlaces] places. Rows that fail show as failed.
  Future<void> loadBasics() async {
    final p = places;
    final account = _account;
    final token = accessToken?.call();
    if (p == null || account == null || token == null || _items.isEmpty || _basicsStatus == SavedLoadStatus.loading) return;
    final generation = _generation;
    _basicsStatus = SavedLoadStatus.loading;
    notifyListeners();
    final answer = await p.savedBasics(accessToken: token);
    if (!_current(generation, account)) return;
    if (answer == null) {
      _basicsStatus = SavedLoadStatus.failed;
    } else {
      for (final b in answer) {
        _basics[b.placeId] = b;
      }
      _basicsStatus = SavedLoadStatus.loaded;
    }
    notifyListeners();
  }

  /// Runs one change for the current account and applies [onOk] only if the
  /// server confirmed it and the account is still the same. Nothing can be
  /// changed before the list has loaded (whether a place is saved isn't
  /// known yet). A lost answer may still have been applied: the list is read
  /// again so the screen shows what is stored.
  Future<SavedOutcome> _change(Future<SavedOutcome> Function(SavedPlacesService s) call, void Function() onOk) async {
    final s = service;
    final account = _account;
    if (s == null || account == null) return SavedOutcome.failed;
    if (_status != SavedLoadStatus.loaded) return SavedOutcome.notReady;
    final generation = _generation;
    final write = call(s);
    // A write that times out keeps running: when it finally settles (either
    // way) the list is read again, so a late commit still shows.
    var timedOut = false;
    final outcome = await write.timeout(writeTimeout, onTimeout: () {
      timedOut = true;
      return SavedOutcome.network;
    });
    if (timedOut) {
      unawaited(write.then((_) {
        if (_current(generation, account)) {
          _changes++;
          unawaited(load());
        }
      }, onError: (_) {}));
    }
    if (!_current(generation, account)) return SavedOutcome.failed;
    if (outcome == SavedOutcome.ok) {
      _changes++;
      onOk();
      notifyListeners();
    } else if (outcome == SavedOutcome.network) {
      _changes++;
      unawaited(load());
    }
    return outcome;
  }

  /// Saves [placeId] as Want to go (the bookmark on the pick).
  Future<SavedOutcome> add(String placeId) => _change((s) => s.add(placeId), () {
        if (!contains(placeId)) _items = [SavedPlace(placeId: placeId), ..._items];
      });

  Future<SavedOutcome> remove(String placeId) => _change((s) => s.remove(placeId), () {
        _items = [for (final p in _items) if (p.placeId != placeId) p];
        _basics.remove(placeId);
      });

  Future<SavedOutcome> setStatus(String placeId, SavedStatus status) =>
      _change((s) => s.update(placeId, status: status), () => _replace(placeId, (p) => p.copyWith(status: status)));

  Future<SavedOutcome> setNote(String placeId, String note) {
    final trimmed = note.trim();
    return _change(
      (s) => trimmed.isEmpty ? s.update(placeId, clearNote: true) : s.update(placeId, note: trimmed),
      () => _replace(placeId, (p) => trimmed.isEmpty ? p.copyWith(clearNote: true) : p.copyWith(note: trimmed)),
    );
  }

  void _replace(String placeId, SavedPlace Function(SavedPlace) f) {
    _items = [for (final p in _items) p.placeId == placeId ? f(p) : p];
  }
}
