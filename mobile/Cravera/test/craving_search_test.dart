import 'dart:async';
import 'dart:typed_data';

import 'package:cravera/models/restaurant.dart';
import 'package:cravera/services/craving_search.dart';
import 'package:cravera/services/location_service.dart';
import 'package:cravera/services/places_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Fictional data only; no network.

const here = SearchLocation(latitude: 10, longitude: 20, label: 'Near you');

Restaurant place(String id) => Restaurant(placeId: id, name: 'Test Place $id', latitude: 10.001, longitude: 20.001);

/// Answers searches from a script and records every request.
class FakePlaces extends PlacesService {
  FakePlaces(this.answer, {this.photo}) : super(publishableKey: 'sb_publishable_test');

  /// Returns results for a query, or throws a [PlacesSearchException].
  FutureOr<List<Restaurant>> Function(String query) answer;

  /// The intent each answer carries; none by default.
  Map<String, Object?>? intent;
  final previousIntents = <Map<String, Object?>?>[];
  final localHours = <int?>[];
  final radii = <int?>[];
  final excluded = <List<String>?>[];

  /// Returns photo bytes for a photo name; no photo when not set.
  FutureOr<Uint8List?> Function(String name)? photo;

  /// Avatar links asked for; none loads (the initial shows).
  final avatarRequests = <String>[];

  @override
  Future<Uint8List?> avatarBytes(String avatarUri) async {
    avatarRequests.add(avatarUri);
    return null;
  }

  final queries = <String>[];
  final locations = <SearchLocation>[];
  final photoRequests = <String>[];

  @override
  Future<SearchAnswer> search({
    required String query,
    required SearchLocation near,
    int? radiusMeters,
    Map<String, Object?>? previousIntent,
    int? localHour,
    List<String>? excludePlaceIds,
  }) async {
    excluded.add(excludePlaceIds);
    queries.add(query);
    locations.add(near);
    previousIntents.add(previousIntent);
    localHours.add(localHour);
    radii.add(radiusMeters);
    return SearchAnswer(await answer(query), intent: intent);
  }

  @override
  Future<Uint8List?> photoBytes(String photoName) async {
    photoRequests.add(photoName);
    return photo?.call(photoName);
  }
}

void main() {
  test('a search shows the first result, around the given location', () async {
    final places = FakePlaces((_) => [place('a'), place('b')]);
    final search = CravingSearch(places: places);

    await search.start('  ramen ', here);

    expect(search.status, SearchStatus.showing);
    expect(search.current?.placeId, 'a');
    expect(search.query, 'ramen');
    expect(places.queries, ['ramen']);
    expect(places.locations.single.latitude, 10);
  });

  test('No shows the next result without a new request, then runs out', () async {
    final places = FakePlaces((_) => [place('a'), place('b'), place('c')]);
    final search = CravingSearch(places: places);
    await search.start('ramen', here);

    search.next();
    expect(search.current?.placeId, 'b');
    search.next();
    expect(search.current?.placeId, 'c');
    expect(places.queries, hasLength(1), reason: 'No never asks the server again');

    search.next();
    expect(search.status, SearchStatus.exhausted);
    expect(search.foundNothing, isFalse);
    expect(search.current, isNull);
    expect(search.rejections, 3);
  });

  test('no results at all is "found nothing", not an error', () async {
    final search = CravingSearch(places: FakePlaces((_) => []));
    await search.start('ramen', here);
    expect(search.status, SearchStatus.exhausted);
    expect(search.foundNothing, isTrue);
  });

  test('refine runs a new search with the added text and starts from the top', () async {
    final places = FakePlaces((q) => q == 'ramen' ? [place('a')] : [place('x'), place('y')]);
    final search = CravingSearch(places: places);
    await search.start('ramen', here);
    search.next();
    expect(search.status, SearchStatus.exhausted);

    await search.refine('  spicy ');

    expect(places.queries, ['ramen', 'ramen spicy']);
    expect(search.query, 'ramen spicy');
    expect(search.current?.placeId, 'x');
    expect(search.rejections, 0);
  });

  test('each failure is reported, and retry repeats the same search', () async {
    for (final error in PlacesSearchError.values) {
      var fail = true;
      final places = FakePlaces((_) => fail ? throw PlacesSearchException(error) : [place('a')]);
      final search = CravingSearch(places: places);

      await search.start('ramen', here);
      expect(search.status, SearchStatus.failed, reason: '$error');
      expect(search.error, error);

      fail = false;
      await search.retry();
      expect(search.status, SearchStatus.showing, reason: '$error');
      expect(places.queries, ['ramen', 'ramen']);
    }
  });

  test('without a publishable key every search fails as not configured', () async {
    final search = CravingSearch();
    await search.start('ramen', here);
    expect(search.status, SearchStatus.failed);
    expect(search.error, PlacesSearchError.notConfigured);
  });

  test('the newest search wins: a slow older answer is dropped', () async {
    final slow = Completer<List<Restaurant>>();
    final places = FakePlaces((q) => q == 'slow' ? slow.future : [place('new')]);
    final search = CravingSearch(places: places);

    final first = search.start('slow', here);
    await search.start('fast', here);
    slow.complete([place('old')]);
    await first;

    expect(search.query, 'fast');
    expect(search.current?.placeId, 'new');
  });

  test('reset drops a search still in flight', () async {
    final slow = Completer<List<Restaurant>>();
    final search = CravingSearch(places: FakePlaces((_) => slow.future));

    final pending = search.start('ramen', here);
    search.reset();
    slow.complete([place('late')]);
    await pending;

    expect(search.status, SearchStatus.idle);
    expect(search.current, isNull);
  });

  test('a refine never shows a place already said No to, and sends their IDs (TASK-005)', () async {
    // The server keeps answering with the same places, rejected ones first.
    final places = FakePlaces((_) => [place('a'), place('b'), place('c'), place('d')]);
    places.intent = {'textQuery': 'tacos'};
    final search = CravingSearch(places: places);
    await search.start('tacos', here);
    expect(search.current?.placeId, 'a');
    search.next();
    expect(search.current?.placeId, 'b');

    await search.refine('cheaper');
    expect(places.excluded.last, ['a', 'b'], reason: 'the server is told what was shown');
    expect(search.current?.placeId, 'c', reason: 'never a place already seen');
    search.next();
    expect(search.current?.placeId, 'd');

    await search.refine('no seafood');
    expect(places.excluded.last, ['a', 'b', 'c', 'd']);
    expect(search.status, SearchStatus.exhausted, reason: 'everything was already seen');
    expect(search.noNewPlaces, isTrue, reason: '"no new places", not "nothing open"');

    // A new craving is a new session.
    await search.start('ramen', here);
    expect(places.excluded.last, isNull);
    expect(search.current?.placeId, 'a');
  });

  test('after more than 100 places, the earliest still never comes back', () async {
    var batch = 0;
    // Each answer: 30 new places, plus the very first place again.
    final places = FakePlaces((_) {
      final start = batch++ * 30;
      return [place('p0'), for (var i = start; i < start + 30; i++) place('p${i + 1}')];
    });
    places.intent = {'textQuery': 'tacos'};
    final search = CravingSearch(places: places);
    await search.start('tacos', here);
    for (var round = 0; round < 5; round++) {
      while (search.status == SearchStatus.showing) {
        search.next();
      }
      await search.refine('more');
    }
    expect(places.excluded.last!.length, CravingSearch.maxExcluded, reason: 'the request stays capped');
    expect(places.excluded.last, isNot(contains('p0')), reason: 'the oldest fell off the request');
    expect(search.current?.placeId, isNot('p0'), reason: 'but the app still filters it');
  });

  test('refreshing an expired refine never brings back a place said No to', () async {
    var now = DateTime(2026, 1, 1, 12);
    final places = FakePlaces((_) => [place('a'), place('b'), place('c')]);
    places.intent = {'textQuery': 'tacos'};
    final search = CravingSearch(places: places, clock: () => now);
    await search.start('tacos', here);
    await search.refine('cheaper'); // shows b (a was shown first)
    expect(search.current?.placeId, 'b');
    search.next(); // No to b
    expect(search.current?.placeId, 'c');
    now = now.add(const Duration(minutes: 16));
    expect(search.checkFresh(), isFalse);
    await search.retry(); // "Search again"
    expect(search.current?.placeId, 'c', reason: 'b was said No to; c is still fine to show');
    expect(places.excluded.last, containsAll(['a', 'b']));
  });

  test('a retry sends the same exclusions as the request it repeats', () async {
    var fail = false;
    final places = FakePlaces((_) => fail ? throw const PlacesSearchException(PlacesSearchError.network) : [place('a'), place('b'), place('c')]);
    places.intent = {'textQuery': 'tacos'};
    final search = CravingSearch(places: places);
    await search.start('tacos', here);
    fail = true;
    await search.refine('cheaper');
    expect(search.status, SearchStatus.failed);
    fail = false;
    await search.retry();
    expect(places.excluded.sublist(1), [['a'], ['a']]);
    expect(search.current?.placeId, 'b');
  });

  test('results older than 15 minutes expire before No or Yes can use them', () async {
    var now = DateTime(2026, 1, 1, 12);
    final places = FakePlaces((_) => [place('a'), place('b')]);
    final search = CravingSearch(places: places, clock: () => now);
    await search.start('ramen', here);

    now = now.add(const Duration(minutes: 15));
    expect(search.checkFresh(), isTrue, reason: 'exactly 15 minutes is still fresh');

    now = now.add(const Duration(seconds: 1));
    search.next();
    expect(search.status, SearchStatus.expired, reason: 'No checks the age first');
    expect(search.current, isNull);

    await search.retry();
    expect(search.status, SearchStatus.showing);
    expect(search.current?.placeId, 'a');
    expect(places.queries, ['ramen', 'ramen']);
  });

  test('a craving longer than the server accepts fails without a request', () async {
    final places = FakePlaces((_) => [place('a')]);
    final search = CravingSearch(places: places);

    await search.start('x' * (CravingSearch.maxQueryLength + 1), here);
    expect(search.status, SearchStatus.failed);
    expect(search.error, PlacesSearchError.rejected);
    expect(search.queryTooLong, isTrue);
    expect(places.queries, isEmpty);

    await search.start('x' * CravingSearch.maxQueryLength, here);
    expect(search.status, SearchStatus.showing, reason: 'exactly the limit is fine');
  });

  test('a refine that makes the craving too long is stopped, not sent', () async {
    final places = FakePlaces((_) => [place('a')]);
    final search = CravingSearch(places: places);
    await search.start('x' * (CravingSearch.maxQueryLength - 3), here);

    await search.refine('spicy');
    expect(search.queryTooLong, isTrue);
    expect(places.queries, hasLength(1));
  });

  test('only the first pick gets a photo; No makes no Google request', () async {
    Restaurant withPhoto(String id) =>
        Restaurant(placeId: id, name: 'Test Place $id', photoName: 'places/$id/photos/p', latitude: 10, longitude: 20);
    final places = FakePlaces(
      (_) => [withPhoto('a'), withPhoto('b'), withPhoto('c')],
      photo: (name) => Uint8List.fromList(name.split('/')[1].codeUnits),
    );
    final search = CravingSearch(places: places);

    await search.start('ramen', here);
    await Future<void>.delayed(Duration.zero);
    expect(places.photoRequests, ['places/a/photos/p'], reason: 'not all 20 results');
    expect(search.currentPhoto, 'a'.codeUnits);

    search.next();
    search.next();
    await Future<void>.delayed(Duration.zero);
    expect(places.photoRequests, ['places/a/photos/p'], reason: 'photos stay free: first pick only');
    expect(search.currentPhoto, isNull, reason: 'later picks show the placeholder');
  });

  test('no photo, or a failed photo, leaves the card without one', () async {
    final places = FakePlaces(
      (_) => [place('no-name'), Restaurant(placeId: 'x', name: 'X', photoName: 'places/x/photos/p', latitude: 1, longitude: 2)],
    );
    final search = CravingSearch(places: places);
    await search.start('ramen', here);
    await Future<void>.delayed(Duration.zero);
    expect(places.photoRequests, isEmpty, reason: 'a place without a photo name asks for nothing');
    expect(search.currentPhoto, isNull);

    search.next();
    await Future<void>.delayed(Duration.zero);
    expect(places.photoRequests, isEmpty);
    expect(search.currentPhoto, isNull);
  });

  test('a photo that arrives after a new search is dropped', () async {
    final late = Completer<Uint8List?>();
    final places = FakePlaces(
      (q) => [Restaurant(placeId: q, name: q, photoName: 'places/$q/photos/p', latitude: 1, longitude: 2)],
      photo: (name) => name.contains('old') ? late.future : null,
    );
    final search = CravingSearch(places: places);
    await search.start('old', here);
    await search.start('new', here);
    late.complete(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(search.current?.placeId, 'new');
    expect(search.currentPhoto, isNull);
  });

  test('empty cravings are ignored', () async {
    final places = FakePlaces((_) => [place('a')]);
    final search = CravingSearch(places: places);
    await search.start('   ', here);
    expect(search.status, SearchStatus.idle);
    expect(places.queries, isEmpty);
  });

  test('refine sends only the added text with the current intent, so the server changes the search', () async {
    final places = FakePlaces((_) => [place('a')])..intent = {'textQuery': 'tacos', 'priceLevels': <int>[]};
    final search = CravingSearch(places: places, clock: () => DateTime(2026, 11, 26, 21, 30));
    await search.start('cheap late-night tacos', here);
    await search.refine(' cheaper ');

    expect(places.queries, ['cheap late-night tacos', 'cheaper']);
    expect(places.previousIntents, [null, {'textQuery': 'tacos', 'priceLevels': <int>[]}]);
    expect(places.localHours, [21, 21]);
    expect(search.query, 'cheap late-night tacos cheaper', reason: 'the screen still shows the whole craving');
  });

  test('retry after a failed refine resends the same refine', () async {
    var fail = false;
    final places = FakePlaces((_) => fail ? throw const PlacesSearchException(PlacesSearchError.network) : [place('a')])
      ..intent = {'textQuery': 'tacos'};
    final search = CravingSearch(places: places);
    await search.start('tacos', here);
    fail = true;
    await search.refine('no seafood');
    expect(search.status, SearchStatus.failed);
    fail = false;
    await search.retry();

    expect(places.queries, ['tacos', 'no seafood', 'no seafood']);
    expect(places.previousIntents.last, {'textQuery': 'tacos'});
  });
}
