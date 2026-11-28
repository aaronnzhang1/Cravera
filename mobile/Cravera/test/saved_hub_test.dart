import 'dart:async';

import 'package:cravera/services/places_service.dart';
import 'package:cravera/services/saved_hub.dart';
import 'package:cravera/services/saved_places_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_saved_places.dart';

// Fictional data only; no network.

/// Answers saved-place basics from a script and records each request.
class FakeBasics extends PlacesService {
  FakeBasics() : super(publishableKey: 'sb_publishable_test');
  final requests = <List<String>>[];
  bool fails = false;
  Completer<void>? gate;

  /// The places the function would read from the caller's rows.
  List<String> rows = const [];

  @override
  Future<List<SavedBasics>?> savedBasics({required String accessToken}) async {
    final placeIds = rows;
    requests.add(placeIds);
    await gate?.future;
    if (fails) return null;
    return [
      for (final id in placeIds)
        id == 'gone'
            ? SavedBasics(placeId: id, missing: true)
            : SavedBasics(placeId: id, name: 'Test Place $id', address: '1 Fictional St', city: id.startsWith('b') ? 'Testburg' : 'Testville'),
    ];
  }
}

void main() {
  test('signing in loads that account; switching accounts clears it first', () async {
    final service = FakeSavedPlaces()..rows.add(const SavedPlace(placeId: 'a1', note: 'A note'));
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    await pumpEventQueue();
    expect(hub.items.map((p) => p.placeId), ['a1']);

    service.rows
      ..clear()
      ..add(const SavedPlace(placeId: 'b1'));
    hub.switchAccount('account-b');
    expect(hub.items, isEmpty, reason: 'A\'s places are gone before B\'s load');
    await pumpEventQueue();
    expect(hub.items.map((p) => p.placeId), ['b1']);

    hub.switchAccount(null);
    expect(hub.items, isEmpty);
  });

  test('a list that answers after the account changed is dropped', () async {
    final service = FakeSavedPlaces()
      ..rows.add(const SavedPlace(placeId: 'a1'))
      ..listGate = Completer<void>();
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    hub.switchAccount(null); // signed out while loading
    service.listGate!.complete();
    await pumpEventQueue();
    expect(hub.items, isEmpty);
  });

  test('a failed load shows failed and can be tried again', () async {
    final service = FakeSavedPlaces()..listFails = true;
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    await pumpEventQueue();
    expect(hub.status, SavedLoadStatus.failed);
    service.listFails = false;
    await hub.load();
    expect(hub.status, SavedLoadStatus.loaded);
  });

  test('changes apply only after the server confirms; a failure keeps the old state', () async {
    final service = FakeSavedPlaces();
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    await pumpEventQueue();

    expect(await hub.add('p1'), SavedOutcome.ok);
    expect(hub.contains('p1'), isTrue);
    expect(await hub.setStatus('p1', SavedStatus.been), SavedOutcome.ok);
    expect(hub.byStatus(SavedStatus.been).single.placeId, 'p1');
    expect(await hub.setNote('p1', '  Try the noodles  '), SavedOutcome.ok);
    expect(hub.items.single.note, 'Try the noodles');

    service.failWith = SavedOutcome.network;
    expect(await hub.setStatus('p1', SavedStatus.wantToGo), SavedOutcome.network);
    expect(hub.items.single.status, SavedStatus.been, reason: 'old state kept');
    expect(await hub.remove('p1'), SavedOutcome.network);
    expect(hub.contains('p1'), isTrue);

    service.failWith = null;
    expect(await hub.setNote('p1', ''), SavedOutcome.ok);
    expect(hub.items.single.note, isNull, reason: 'an empty note clears it');
    expect(await hub.remove('p1'), SavedOutcome.ok);
    expect(hub.items, isEmpty);
  });

  test('a guest or signed-out hub saves nothing', () async {
    final hub = SavedHub(service: FakeSavedPlaces());
    expect(await hub.add('p1'), SavedOutcome.failed);
    expect(hub.items, isEmpty);
  });

  test('basics: one request per open for the saved places, per-place results, dropped after a switch', () async {
    final service = FakeSavedPlaces()..rows.addAll(const [SavedPlace(placeId: 'a1'), SavedPlace(placeId: 'b2'), SavedPlace(placeId: 'gone')]);
    final places = FakeBasics()..rows = const ['a1', 'b2', 'gone'];
    final hub = SavedHub(service: service, places: places, accessToken: () => 'fake-token');
    hub.switchAccount('account-a');
    await pumpEventQueue();
    await hub.loadBasics();
    expect(places.requests, [
      ['a1', 'b2', 'gone'],
    ]);
    expect(hub.basics('a1')!.city, 'Testville');
    expect(hub.basics('b2')!.city, 'Testburg');
    expect(hub.basics('gone')!.missing, isTrue);

    places.gate = Completer<void>();
    final late = hub.loadBasics();
    hub.switchAccount('account-b');
    places.gate!.complete();
    await late;
    expect(hub.basics('a1'), isNull, reason: 'A\'s places never show for B');
  });

  test('basics that fail show as failed', () async {
    final service = FakeSavedPlaces()..rows.add(const SavedPlace(placeId: 'a1'));
    final places = FakeBasics()..fails = true;
    final hub = SavedHub(service: service, places: places, accessToken: () => 'fake-token');
    hub.switchAccount('account-a');
    await pumpEventQueue();
    await hub.loadBasics();
    expect(hub.basicsStatus, SavedLoadStatus.failed);
  });

  test('nothing can be toggled before the list has loaded', () async {
    final service = FakeSavedPlaces()..listGate = Completer<void>();
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    expect(await hub.add('p1'), SavedOutcome.notReady);
    expect(service.rows, isEmpty);
    service.listGate!.complete();
  });

  test('an older list read can\u2019t erase a bookmark confirmed after it started', () async {
    final service = FakeSavedPlaces();
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    await pumpEventQueue();
    service.listGate = Completer<void>();
    final staleRead = hub.load(); // reads before the save
    final snapshotRows = <SavedPlace>[];
    expect(snapshotRows, isEmpty);
    expect(await hub.add('p1'), SavedOutcome.ok);
    service.listGate!.complete();
    service.listGate = null;
    await staleRead;
    await pumpEventQueue();
    expect(hub.contains('p1'), isTrue);
  });

  test('a lost answer re-reads the list, so a change that did land shows', () async {
    final service = FakeSavedPlaces()..rows.add(const SavedPlace(placeId: 'p1'));
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    await pumpEventQueue();
    // The delete reaches the server but its answer is lost.
    service.rows.clear();
    service.failWith = SavedOutcome.network;
    expect(await hub.remove('p1'), SavedOutcome.network);
    service.failWith = null;
    await pumpEventQueue();
    expect(hub.contains('p1'), isFalse, reason: 'the re-read shows it is gone');
  });

  test('without an access token no basics are asked for', () async {
    final service = FakeSavedPlaces()..rows.add(const SavedPlace(placeId: 'a1'));
    final places = FakeBasics()..rows = const ['a1'];
    final hub = SavedHub(service: service, places: places, accessToken: () => null);
    hub.switchAccount('account-a');
    await pumpEventQueue();
    await hub.loadBasics();
    expect(places.requests, isEmpty);
  });

  test('a write that times out and commits later is shown once it settles', () async {
    final service = _SlowRemove()..rows.add(const SavedPlace(placeId: 'p1'));
    final hub = SavedHub(service: service, writeTimeout: const Duration(milliseconds: 20));
    hub.switchAccount('account-a');
    await pumpEventQueue();
    expect(await hub.remove('p1'), SavedOutcome.network); // the app stops waiting
    await pumpEventQueue();
    expect(hub.contains('p1'), isTrue, reason: 'the first re-read ran before the delete landed');
    service.finish(); // the delete commits now
    await pumpEventQueue();
    expect(hub.contains('p1'), isFalse, reason: 're-read again once the write settled');
  });

  test('a newer note never lands before an older, timed-out one', () async {
    final service = _GatedNotes()..rows.add(const SavedPlace(placeId: 'p1'));
    final hub = SavedHub(service: service, writeTimeout: const Duration(milliseconds: 20));
    hub.switchAccount('account-a');
    await pumpEventQueue();
    expect(await hub.setNote('p1', 'first'), SavedOutcome.network); // still on its way
    expect(await hub.setNote('p1', 'second'), SavedOutcome.pending, reason: 'not queued behind an unconfirmed write');
    expect(service.sent, ['first']);
    service.release();
    await pumpEventQueue();
    expect(await hub.setNote('p1', 'second'), SavedOutcome.ok);
    expect(service.sent, ['first', 'second']);
    await pumpEventQueue();
    expect(hub.items.single.note, 'second');
  });

  test('an older list read that answers last is dropped', () async {
    final service = _GatedLists()..rows.add(const SavedPlace(placeId: 'p1', note: 'old'));
    final hub = SavedHub(service: service);
    hub.switchAccount('account-a');
    service.releaseNext(); // the first load
    await pumpEventQueue();
    final older = hub.load(); // snapshot: note 'old'
    service.rows[0] = const SavedPlace(placeId: 'p1', note: 'new'); // another phone edits
    final newer = hub.load(); // snapshot: note 'new'
    service.releaseLast(); // the newer answers first
    await pumpEventQueue();
    service.releaseNext(); // then the older
    await older;
    await newer;
    expect(hub.items.single.note, 'new');
  });
}

/// Note updates that settle only when released, recording what was sent.
class _GatedNotes extends FakeSavedPlaces {
  final sent = <String?>[];
  final _gates = <Completer<void>>[];
  void release() {
    for (final g in _gates) {
      if (!g.isCompleted) g.complete();
    }
  }

  @override
  Future<SavedOutcome> update(String placeId, {SavedStatus? status, String? note, bool clearNote = false}) async {
    sent.add(note);
    if (sent.length == 1) {
      final g = Completer<void>();
      _gates.add(g);
      await g.future;
    }
    return super.update(placeId, status: status, note: note, clearNote: clearNote);
  }
}

/// List reads that take their snapshot at once and answer when released.
class _GatedLists extends FakeSavedPlaces {
  final _pending = <(Completer<void>, List<SavedPlace>)>[];
  void releaseNext() => _pending.removeAt(0).$1.complete();
  void releaseLast() => _pending.removeLast().$1.complete();

  @override
  Future<List<SavedPlace>?> list() async {
    final snapshot = List.of(rows);
    final gate = Completer<void>();
    _pending.add((gate, snapshot));
    await gate.future;
    return snapshot;
  }
}

/// A remove that commits only when told to (a slow network).
class _SlowRemove extends FakeSavedPlaces {
  final _done = Completer<void>();
  void finish() {
    rows.clear();
    _done.complete();
  }

  @override
  Future<SavedOutcome> remove(String placeId) async {
    await _done.future;
    return SavedOutcome.ok;
  }
}
