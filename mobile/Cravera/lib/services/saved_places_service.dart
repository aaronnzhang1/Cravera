import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a saved place sits in the Saved hub.
enum SavedStatus {
  wantToGo('want_to_go'),
  been('been');

  const SavedStatus(this.column);

  /// The value stored in `saved_places.status`.
  final String column;

  static SavedStatus? fromColumn(Object? v) => switch (v) {
        'want_to_go' => SavedStatus.wantToGo,
        'been' => SavedStatus.been,
        _ => null,
      };
}

/// One saved place as stored: the place ID and the person's own data only.
/// Names, addresses and photos are never stored (Google's terms); they are
/// fetched fresh when shown.
class SavedPlace {
  const SavedPlace({required this.placeId, this.status = SavedStatus.wantToGo, this.note});

  final String placeId;
  final SavedStatus status;
  final String? note;

  /// Same limit as the table check.
  static const maxNoteLength = 500;

  /// Same format as the table check and the Edge Functions.
  static final placeIdFormat = RegExp(r'^[A-Za-z0-9_-]{1,300}$');

  SavedPlace copyWith({SavedStatus? status, String? note, bool clearNote = false}) =>
      SavedPlace(placeId: placeId, status: status ?? this.status, note: clearNote ? null : note ?? this.note);
}

enum SavedOutcome { ok, invalid, network, failed }

/// A plain sentence for each failed outcome.
String savedMessage(SavedOutcome outcome) => switch (outcome) {
      SavedOutcome.ok => 'Saved.',
      SavedOutcome.invalid => 'Notes can be up to 500 characters.',
      SavedOutcome.network => 'No connection. Your saved places are as they were.',
      SavedOutcome.failed => 'Couldn’t save right now. Your saved places are as they were.',
    };

/// Reads and writes the signed-in person's own saved places. RLS limits every
/// call to their rows, and `user_id` is set by the database from the token,
/// so this class never sends one. Screens go through the session, so tests
/// can swap in a fake.
abstract class SavedPlacesService {
  /// All of the person's saved places, newest first; null if they can't be read.
  Future<List<SavedPlace>?> list();

  /// Saves [placeId] as Want to go. Already saved counts as ok.
  Future<SavedOutcome> add(String placeId);

  /// Changes the status and/or note of a saved place.
  Future<SavedOutcome> update(String placeId, {SavedStatus? status, String? note, bool clearNote = false});

  /// Removes a saved place.
  Future<SavedOutcome> remove(String placeId);
}

class SupabaseSavedPlacesService implements SavedPlacesService {
  SupabaseSavedPlacesService(this._client);
  final SupabaseClient _client;

  static const _table = 'saved_places';

  static SavedPlace? _fromRow(Map<String, dynamic> row) {
    final id = row['place_id'];
    final status = SavedStatus.fromColumn(row['status']);
    final note = row['note'];
    if (id is! String || !SavedPlace.placeIdFormat.hasMatch(id) || status == null) return null;
    return SavedPlace(placeId: id, status: status, note: note is String && note.isNotEmpty ? note : null);
  }

  Future<SavedOutcome> _guard(Future<void> Function() call) async {
    try {
      await call();
      return SavedOutcome.ok;
    } on SocketException {
      return SavedOutcome.network;
    } on TimeoutException {
      return SavedOutcome.network;
    } on ClientException {
      return SavedOutcome.network;
    } catch (_) {
      return SavedOutcome.failed;
    }
  }

  @override
  Future<List<SavedPlace>?> list() async {
    try {
      final rows = await _client.from(_table).select('place_id, status, note').order('created_at', ascending: false);
      return [for (final r in rows) ?_fromRow(r)];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SavedOutcome> add(String placeId) async {
    if (!SavedPlace.placeIdFormat.hasMatch(placeId)) return SavedOutcome.invalid;
    try {
      await _client.from(_table).insert({'place_id': placeId});
      return SavedOutcome.ok;
    } on PostgrestException catch (e) {
      // Already saved (unique per person and place): the result is what was asked.
      return e.code == '23505' ? SavedOutcome.ok : SavedOutcome.failed;
    } on SocketException {
      return SavedOutcome.network;
    } on TimeoutException {
      return SavedOutcome.network;
    } on ClientException {
      return SavedOutcome.network;
    } catch (_) {
      return SavedOutcome.failed;
    }
  }

  @override
  Future<SavedOutcome> update(String placeId, {SavedStatus? status, String? note, bool clearNote = false}) async {
    final columns = <String, Object?>{
      if (status != null) 'status': status.column,
      if (clearNote) 'note': null,
      if (!clearNote && note != null) 'note': note.trim().isEmpty ? null : note.trim(),
    };
    final text = columns['note'];
    if (columns.isEmpty || (text is String && text.runes.length > SavedPlace.maxNoteLength)) return SavedOutcome.invalid;
    return _guard(() async {
      final rows = await _client.from(_table).update(columns).eq('place_id', placeId).select('place_id');
      // No row back: not saved any more, or not this person's (RLS).
      if (rows.isEmpty) throw StateError('no row');
    });
  }

  @override
  Future<SavedOutcome> remove(String placeId) =>
      _guard(() => _client.from(_table).delete().eq('place_id', placeId));
}
