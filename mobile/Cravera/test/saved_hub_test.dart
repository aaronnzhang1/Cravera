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

  @override
  Future<List<SavedBasics>?> savedBasics(List<String> placeIds) async {
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
    final places = FakeBasics();
    final hub = SavedHub(service: service, places: places);
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
    final hub = SavedHub(service: service, places: places);
    hub.switchAccount('account-a');
    await pumpEventQueue();
    await hub.loadBasics();
    expect(hub.basicsStatus, SavedLoadStatus.failed);
  });
}
