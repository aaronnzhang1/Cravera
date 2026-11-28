import 'dart:async';

import 'package:cravera/services/saved_places_service.dart';

/// An in-memory saved_places for one account, with switchable failures.
/// Fictional data only.
class FakeSavedPlaces implements SavedPlacesService {
  final List<SavedPlace> rows = [];

  /// When set, every change answers this instead of saving.
  SavedOutcome? failWith;

  /// When set, list() waits for it (to test late answers).
  Completer<void>? listGate;
  bool listFails = false;
  int listCalls = 0;

  @override
  Future<List<SavedPlace>?> list() async {
    listCalls++;
    await listGate?.future;
    return listFails ? null : List.of(rows);
  }

  @override
  Future<SavedOutcome> add(String placeId) async {
    if (failWith != null) return failWith!;
    if (!rows.any((r) => r.placeId == placeId)) rows.insert(0, SavedPlace(placeId: placeId));
    return SavedOutcome.ok;
  }

  @override
  Future<SavedOutcome> update(String placeId, {SavedStatus? status, String? note, bool clearNote = false}) async {
    if (failWith != null) return failWith!;
    final i = rows.indexWhere((r) => r.placeId == placeId);
    if (i < 0) return SavedOutcome.failed;
    rows[i] = rows[i].copyWith(status: status, note: note, clearNote: clearNote);
    return SavedOutcome.ok;
  }

  @override
  Future<SavedOutcome> remove(String placeId) async {
    if (failWith != null) return failWith!;
    rows.removeWhere((r) => r.placeId == placeId);
    return SavedOutcome.ok;
  }
}
