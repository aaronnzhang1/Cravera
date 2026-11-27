import 'dart:async';

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
  FakePlaces(this.answer) : super(publishableKey: 'sb_publishable_test');

  /// Returns results for a query, or throws a [PlacesSearchException].
  FutureOr<List<Restaurant>> Function(String query) answer;
  final queries = <String>[];
  final locations = <SearchLocation>[];

  @override
  Future<List<Restaurant>> search({required String query, required SearchLocation near, int? radiusMeters}) async {
    queries.add(query);
    locations.add(near);
    return answer(query);
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

  test('empty cravings are ignored', () async {
    final places = FakePlaces((_) => [place('a')]);
    final search = CravingSearch(places: places);
    await search.start('   ', here);
    expect(search.status, SearchStatus.idle);
    expect(places.queries, isEmpty);
  });
}
