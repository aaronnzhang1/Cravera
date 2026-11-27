import 'dart:async';
import 'dart:typed_data';

import 'package:cravera/core/session.dart';
import 'package:cravera/main.dart';
import 'package:cravera/models/restaurant.dart';
import 'package:cravera/screens/home_screen.dart';
import 'package:cravera/services/craving_search.dart';
import 'package:cravera/services/location_service.dart';
import 'package:cravera/services/places_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'craving_search_test.dart' show FakePlaces;

// Fictional data only; the network and GPS are faked.

const _nearby = SearchLocation(latitude: 10, longitude: 20, label: 'Near you');

class _FoundLocation extends LocationService {
  const _FoundLocation();
  @override
  Future<LocationResult> current() async => const LocationResult.found(_nearby);
}

Restaurant _place(String id, String name) => Restaurant(
      placeId: id,
      name: name,
      cuisine: 'Ramen Restaurant',
      address: '$id Example St',
      latitude: 10.001,
      longitude: 20.001,
      distanceMeters: 150,
    );

Future<void> _settle(WidgetTester tester) async {
  // The logo animates forever, so pumpAndSettle never finishes. Step time instead.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<AppSession> _homeWith(WidgetTester tester, FakePlaces places) async {
  final session = AppSession(locationService: const _FoundLocation(), search: CravingSearch(places: places));
  await tester.pumpWidget(MyApp(session: session));
  await tester.pump();
  await tester.tap(find.text('Continue as guest'));
  await _settle(tester);
  return session;
}

Future<void> _searchFor(WidgetTester tester, String craving) async {
  await tester.enterText(find.widgetWithText(TextField, 'Ask Cravera…'), craving);
  await tester.tap(find.byTooltip('Search'));
  await _settle(tester);
}

void main() {
  testWidgets('a craving shows a real result; No walks the results, then asks to refine', (tester) async {
    final places = FakePlaces((q) => q == 'ramen'
        ? [_place('a', 'Test Noodle House'), _place('b', 'Sample Ramen Bar')]
        : [_place('c', 'Example Spicy Ramen')]);
    await _homeWith(tester, places);

    await _searchFor(tester, 'ramen');
    expect(find.text('Test Noodle House'), findsOneWidget);
    expect(places.locations.single.label, 'Near you', reason: 'searches around the device location');

    await _tapVisible(tester, find.text('No'));
    await _settle(tester);
    expect(find.text('Sample Ramen Bar'), findsOneWidget);

    await _tapVisible(tester, find.text('No'));
    await _settle(tester);
    expect(find.textContaining("That's every open match"), findsOneWidget);
    expect(places.queries, ['ramen'], reason: 'No never makes a new request');

    await tester.enterText(find.widgetWithText(TextField, 'Tell me more…'), 'spicy');
    await tester.tap(find.byTooltip('Search again'));
    await _settle(tester);
    expect(places.queries, ['ramen', 'ramen spicy']);
    expect(find.text('Example Spicy Ramen'), findsOneWidget);
  });

  testWidgets('the card shows the server reasons for the pick, only when there are some', (tester) async {
    final matched = Restaurant(
      placeId: 'm',
      name: 'Test Bowl Bar',
      latitude: 10.001,
      longitude: 20.001,
      reasons: const ['In your price range', 'Close by'],
    );
    await _homeWith(tester, FakePlaces((_) => [matched, _place('b', 'Sample Ramen Bar')]));
    await _searchFor(tester, 'gym food');
    expect(find.text('In your price range · Close by'), findsOneWidget);

    await _tapVisible(tester, find.text('No'));
    await _settle(tester);
    expect(find.textContaining('price range'), findsNothing);
  });

  testWidgets('"Narrow it down" waits for the 5th No, stays small, and can be closed or hidden', (tester) async {
    await _homeWith(tester, FakePlaces((_) => [for (var i = 0; i < 8; i++) _place('$i', 'Test Place $i')]));
    await _searchFor(tester, 'ramen');
    for (var i = 0; i < CravingSearch.offerRefineAfter - 1; i++) {
      await _tapVisible(tester, find.text('No'));
      await _settle(tester);
    }
    expect(find.text('Narrow it down'), findsNothing, reason: 'not before the 5th No');
    expect(find.textContaining('Want to narrow'), findsNothing);

    await _tapVisible(tester, find.text('No'));
    await _settle(tester);
    expect(find.text('Narrow it down'), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsNothing, reason: 'no input until asked');

    await _tapVisible(tester, find.text('Narrow it down'));
    await _settle(tester);
    expect(find.widgetWithText(TextField, 'e.g. cheaper, no seafood'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'e.g. cheaper, no seafood'), 'no seafood');
    await _tapVisible(tester, find.byTooltip('Close'));
    await _settle(tester);
    expect(find.widgetWithText(TextField, 'e.g. cheaper, no seafood'), findsNothing);
    expect(find.text('Narrow it down'), findsOneWidget);

    await _tapVisible(tester, find.byTooltip('Hide'));
    await _settle(tester);
    expect(find.text('Narrow it down'), findsNothing);
    await _tapVisible(tester, find.text('No'));
    await _settle(tester);
    expect(find.text('Narrow it down'), findsNothing, reason: 'stays hidden for this search');

    // A new search with the same words is a new search: the chip can come back,
    // without a draft typed for the old one.
    await _tapVisible(tester, find.text('New craving'));
    await _settle(tester);
    await _searchFor(tester, 'ramen');
    for (var i = 0; i < CravingSearch.offerRefineAfter; i++) {
      await _tapVisible(tester, find.text('No'));
      await _settle(tester);
    }
    expect(find.text('Narrow it down'), findsOneWidget);
    await _tapVisible(tester, find.text('Narrow it down'));
    await _settle(tester);
    expect(find.text('no seafood'), findsNothing, reason: 'the old draft is gone');
  });

  testWidgets('refine chips are always on the pick and refine with the current intent', (tester) async {
    final places = FakePlaces((_) => [_place('a', 'Test Noodle House'), _place('b', 'Sample Ramen Bar')])
      ..intent = {'textQuery': 'ramen'};
    await _homeWith(tester, places);
    await _searchFor(tester, 'ramen');

    for (final label in ['Cheaper', 'Closer', 'Something else']) {
      expect(find.widgetWithText(ActionChip, label), findsOneWidget, reason: 'visible before any No');
    }
    await _tapVisible(tester, find.widgetWithText(ActionChip, 'Cheaper'));
    await _settle(tester);
    expect(places.queries, ['ramen', 'cheaper']);
    expect(places.previousIntents.last, {'textQuery': 'ramen'});
  });

  testWidgets('on a short phone with a home indicator, chips and No / Yes are on screen without scrolling', (tester) async {
    addTearDown(tester.view.reset);
    await _homeWith(tester, FakePlaces((_) => [_place('a', 'A Test Place With A Name Long Enough To Wrap Twice')]));
    await _searchFor(tester, 'ramen');
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1136); // 320 x 568
    tester.view.padding = const FakeViewPadding(bottom: 68); // 34 pt home indicator
    await _settle(tester);

    expect(tester.takeException(), isNull, reason: 'no overflow');
    for (final label in ['Cheaper', 'Closer', 'No', 'Yes']) {
      expect(find.text(label).hitTestable(), findsOneWidget, reason: '$label reachable without scrolling');
    }
    final yesBottom = tester.getBottomLeft(find.text('Yes')).dy;
    expect(yesBottom, lessThanOrEqualTo(568 - 34), reason: 'above the home indicator');
  });

  testWidgets('"Narrow it down" fits with the keyboard open on a short sideways phone', (tester) async {
    addTearDown(tester.view.reset);
    await _homeWith(tester, FakePlaces((_) => [for (var i = 0; i < 8; i++) _place('$i', 'Test Place $i')]));
    await _searchFor(tester, 'ramen');
    for (var i = 0; i < CravingSearch.offerRefineAfter; i++) {
      await _tapVisible(tester, find.text('No'));
      await _settle(tester);
    }
    await _tapVisible(tester, find.text('Narrow it down'));
    await _settle(tester);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1136, 640); // 568 x 320, sideways
    tester.view.viewInsets = const FakeViewPadding(bottom: 400); // 200 pt keyboard
    await _settle(tester);

    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.widgetWithText(TextField, 'e.g. cheaper, no seafood').hitTestable(), findsOneWidget);
  });

  testWidgets('the nav bar hides while a pick is showing and comes back after', (tester) async {
    await _homeWith(tester, FakePlaces((_) => [_place('a', 'Test Noodle House')]));
    expect(find.text('Saved'), findsOneWidget, reason: 'nav bar on Home');

    await _searchFor(tester, 'ramen');
    expect(find.text('Test Noodle House'), findsOneWidget);
    expect(find.text('Saved'), findsNothing, reason: 'no nav bar over the pick');

    await _tapVisible(tester, find.text('New craving'));
    await _settle(tester);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('quick picks on Home each show an icon', (tester) async {
    await _homeWith(tester, FakePlaces((_) => []));
    for (final label in ['Cozy ramen nearby', 'Tacos, open late']) {
      final chip = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
      expect(find.descendant(of: chip, matching: find.byType(Icon)), findsOneWidget, reason: label);
    }
  });

  testWidgets('nothing matched reads like a chat with one-tap ideas and the input at the bottom', (tester) async {
    final places = FakePlaces((q) => q == 'qzxv' ? [] : [_place('a', 'Test Noodle House')])..intent = {'textQuery': 'qzxv'};
    await _homeWith(tester, places);
    await _searchFor(tester, 'qzxv');

    expect(find.textContaining('Nothing open matched'), findsOneWidget);
    expect(find.text('qzxv'), findsOneWidget, reason: "the guest's craving as a bubble");
    final input = tester.getCenter(find.widgetWithText(TextField, 'Tell me more…'));
    final answer = tester.getCenter(find.textContaining('Nothing open matched'));
    expect(input.dy, greaterThan(answer.dy), reason: 'the input sits below the answer, not mid-screen');

    await _tapVisible(tester, find.widgetWithText(ActionChip, 'Something similar'));
    await _settle(tester);
    expect(places.queries, ['qzxv', 'something similar']);
    expect(places.previousIntents.last, {'textQuery': 'qzxv'});
    expect(find.text('Test Noodle House'), findsOneWidget);
  });

  testWidgets('nothing matched on a short sideways phone with the keyboard up: the input stays usable', (tester) async {
    addTearDown(tester.view.reset);
    await _homeWith(tester, FakePlaces((_) => []));
    await _searchFor(tester, 'qzxv');
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1136, 640); // 568 x 320
    await _settle(tester);
    // Focus the field, then the keyboard opens and the layout switches to scrolling.
    await tester.tap(find.widgetWithText(TextField, 'Tell me more…'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 400); // 200 pt keyboard
    await _settle(tester);

    expect(tester.takeException(), isNull, reason: 'no overflow');
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    expect(field.widget.focusNode.hasFocus, isTrue, reason: 'the keyboard stays up through the layout switch');
    await tester.ensureVisible(find.byTooltip('Search again'));
    await tester.pump();
    expect(find.byTooltip('Search again').hitTestable(), findsOneWidget);
  });

  testWidgets('the out-of-results screen fits a short phone with the keyboard open', (tester) async {
    addTearDown(tester.view.reset);
    await _homeWith(tester, FakePlaces((_) => [_place('a', 'Test Noodle House')]));
    await _searchFor(tester, 'a craving long enough to wrap the title onto several lines');
    await _tapVisible(tester, find.text('No'));
    await _settle(tester);
    expect(find.textContaining("That's every open match"), findsOneWidget);

    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1136); // 320 x 568, like an iPhone SE (1st gen)
    tester.view.viewInsets = const FakeViewPadding(bottom: 520); // keyboard: 260 pt
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.text('New search'), findsOneWidget);
  });

  testWidgets('no results says so and offers a refine', (tester) async {
    await _homeWith(tester, FakePlaces((_) => []));
    await _searchFor(tester, 'ramen');
    expect(find.textContaining('Nothing open matched'), findsOneWidget);
    expect(find.text('New search'), findsOneWidget);
  });

  testWidgets('no network shows a message and Try again searches again', (tester) async {
    var offline = true;
    final places = FakePlaces(
        (_) => offline ? throw const PlacesSearchException(PlacesSearchError.network) : [_place('a', 'Test Noodle House')]);
    await _homeWith(tester, places);

    await _searchFor(tester, 'ramen');
    expect(find.text('No connection.'), findsOneWidget);

    offline = false;
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.text('Test Noodle House'), findsOneWidget);
    expect(places.queries, ['ramen', 'ramen']);
  });

  testWidgets('a failing function shows a message, and New search goes back', (tester) async {
    await _homeWith(tester, FakePlaces((_) => throw const PlacesSearchException(PlacesSearchError.server)));
    await _searchFor(tester, 'ramen');
    expect(find.text("Search isn't working right now."), findsOneWidget);

    await tester.tap(find.text('New search'));
    await _settle(tester);
    expect(find.text('What are you craving?'), findsOneWidget);
  });

  testWidgets('the card\'s close button goes back to Home without another search', (tester) async {
    final places = FakePlaces((_) => [_place('a', 'Test Noodle House'), _place('b', 'Sample Ramen Bar')]);
    await _homeWith(tester, places);
    await _searchFor(tester, 'ramen');
    expect(find.text('Test Noodle House'), findsOneWidget);

    await tester.tap(find.text('New craving'));
    await _settle(tester);

    expect(find.text('What are you craving?'), findsOneWidget);
    expect(find.text('Sample Ramen Bar'), findsNothing, reason: 'close is not No');
    expect(places.queries, ['ramen']);
  });

  testWidgets('sign out clears the search and saved places', (tester) async {
    final session = await _homeWith(tester, FakePlaces((_) => [_place('a', 'Test Noodle House')]));
    await _searchFor(tester, 'ramen');
    expect(session.search.status, SearchStatus.showing);
    await tester.tap(find.byTooltip('Bookmark'));
    await _settle(tester);
    session.rateBookmark('a', 4);
    expect(session.bookmarks, hasLength(1));

    session.signOut();
    await _settle(tester);
    expect(session.search.status, SearchStatus.idle);
    expect(session.search.query, isEmpty);
    expect(session.bookmarks, isEmpty, reason: 'the next person must not see saved places');
    expect(session.bookmarkRating('a'), 0);
  });

  testWidgets('a too-long craving says so and offers no pointless retry', (tester) async {
    final places = FakePlaces((_) => [_place('a', 'Test Noodle House')]);
    await _homeWith(tester, places);
    await _searchFor(tester, 'x' * (CravingSearch.maxQueryLength + 1));
    expect(find.text('That craving is too long.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('New search'), findsOneWidget);
    expect(places.queries, isEmpty);
  });

  testWidgets('expired results ask for a fresh search', (tester) async {
    var now = DateTime(2026, 1, 1, 12);
    final places = FakePlaces((_) => [_place('a', 'Test Noodle House')]);
    final session = AppSession(
      locationService: const _FoundLocation(),
      search: CravingSearch(places: places, clock: () => now),
    );
    await tester.pumpWidget(MyApp(session: session));
    await tester.pump();
    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);
    await _searchFor(tester, 'ramen');

    now = now.add(const Duration(minutes: 20));
    await _tapVisible(tester, find.text('Yes'));
    await _settle(tester);
    expect(find.text('These results are out of date.'), findsOneWidget);
    expect(find.text('Navigate there'), findsNothing, reason: 'no directions from an old "open now"');

    await tester.tap(find.text('Search again'));
    await _settle(tester);
    expect(find.text('Test Noodle House'), findsOneWidget);
    expect(places.queries, ['ramen', 'ramen']);
  });

  testWidgets('a pick that goes stale on a redraw brings the nav bar back with the out-of-date screen', (tester) async {
    var now = DateTime(2026, 1, 1, 12);
    final session = AppSession(
      locationService: const _FoundLocation(),
      search: CravingSearch(places: FakePlaces((_) => [_place('a', 'Test Noodle House')]), clock: () => now),
    );
    await tester.pumpWidget(MyApp(session: session));
    await tester.pump();
    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);
    await _searchFor(tester, 'ramen');
    expect(find.text('Saved'), findsNothing);

    // Time passes with no tap; something else redraws Home.
    now = now.add(const Duration(minutes: 20));
    session.toggleBookmark(_place('z', 'Other'));
    await _settle(tester);
    expect(find.text('These results are out of date.'), findsOneWidget);
    expect(session.search.status, SearchStatus.expired);
    expect(find.text('Saved'), findsOneWidget, reason: 'nav bar is back');
  });

  testWidgets('the directions sheet checks freshness again before opening Maps', (tester) async {
    var now = DateTime(2026, 1, 1, 12);
    final session = AppSession(
      locationService: const _FoundLocation(),
      search: CravingSearch(places: FakePlaces((_) => [_place('a', 'Test Noodle House')]), clock: () => now),
    );
    await tester.pumpWidget(MyApp(session: session));
    await tester.pump();
    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);
    await _searchFor(tester, 'ramen');

    await _tapVisible(tester, find.text('Yes'));
    await _settle(tester);
    expect(find.text('Navigate there'), findsOneWidget);

    now = now.add(const Duration(minutes: 20)); // the sheet stayed open
    await tester.tap(find.text('Navigate there'));
    await _settle(tester);
    expect(session.search.status, SearchStatus.expired);
    expect(find.text('These results are out of date.'), findsOneWidget);
  });

  testWidgets('coming back to the app after the results expire hides the card', (tester) async {
    var now = DateTime(2026, 1, 1, 12);
    final session = AppSession(
      locationService: const _FoundLocation(),
      search: CravingSearch(places: FakePlaces((_) => [_place('a', 'Test Noodle House')]), clock: () => now),
    );
    await tester.pumpWidget(MyApp(session: session));
    await tester.pump();
    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);
    await _searchFor(tester, 'ramen');
    expect(find.text('Test Noodle House'), findsOneWidget);

    now = now.add(const Duration(minutes: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    expect(find.text('Test Noodle House'), findsNothing);
    expect(find.text('These results are out of date.'), findsOneWidget);
  });

  testWidgets('no search runs while a typed place is still being looked up', (tester) async {
    final lookup = Completer<SearchLocation?>();
    final places = FakePlaces((_) => [_place('a', 'Test Noodle House')]);
    final session = AppSession(locationService: _SlowLookup(lookup), search: CravingSearch(places: places));
    await tester.pumpWidget(MyApp(session: session));
    await tester.pump();
    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);

    final changing = session.useTypedPlace('Elsewhere Example');
    await _searchFor(tester, 'ramen');
    expect(find.textContaining('Still finding your location'), findsOneWidget);
    expect(places.queries, isEmpty, reason: 'it would have used the area being left');

    lookup.complete(const SearchLocation(latitude: 30, longitude: 40, label: 'Elsewhere Example'));
    await changing;
    await tester.pump(const Duration(seconds: 5)); // let the message bar go away
    await _settle(tester);
    await tester.tap(find.byTooltip('Search'));
    await _settle(tester);
    expect(places.locations.single.label, 'Elsewhere Example');
  });

  test('switching to device location during a typed lookup leaves search usable', () async {
    for (final typedFinishesFirst in [true, false]) {
      final lookup = Completer<SearchLocation?>();
      final session = AppSession(locationService: _SlowLookup(lookup));

      final typed = session.useTypedPlace('Elsewhere Example');
      expect(session.locationChanging, isTrue);
      if (typedFinishesFirst) {
        lookup.complete(const SearchLocation(latitude: 30, longitude: 40, label: 'Elsewhere Example'));
      }
      await session.useDeviceLocation();
      if (!typedFinishesFirst) {
        lookup.complete(const SearchLocation(latitude: 30, longitude: 40, label: 'Elsewhere Example'));
      }
      await typed;

      expect(session.locationChanging, isFalse, reason: 'typed finishes first: $typedFinishesFirst');
      expect(session.searchLocation?.label, 'Near you', reason: 'the newer device choice wins');
    }
  });

  test('a new search area drops the search, including one still waiting', () async {
    final slow = Completer<List<Restaurant>>();
    final session = AppSession(
      locationService: const _MovableLocation(),
      search: CravingSearch(places: FakePlaces((_) => slow.future)),
    );
    await session.useDeviceLocation();
    final pending = session.search.start('ramen', session.searchLocation!);

    await session.useTypedPlace('Elsewhere Example');
    slow.complete([_place('old-area', 'Old Area Noodles')]);
    await pending;

    expect(session.searchLocation?.label, 'Elsewhere Example');
    expect(session.search.status, SearchStatus.idle);
    expect(session.search.current, isNull);
  });

  testWidgets('a photo shows its author''s credit, and the card credits Google Maps', (tester) async {
    final places = FakePlaces(
      (_) => [
        const Restaurant(
          placeId: 'a',
          name: 'Test Noodle House',
          photoName: 'places/a/photos/p',
          photoAuthor: 'Test Photographer',
          latitude: 10.001,
          longitude: 20.001,
        ),
      ],
      photo: (_) => Uint8List.fromList([1, 2, 3]),
    );
    await _homeWith(tester, places);
    await _searchFor(tester, 'ramen');
    expect(find.text('Photo: Test Photographer'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
  });

  testWidgets('no photo means no photo credit', (tester) async {
    await _homeWith(tester, FakePlaces((_) => [_place('a', 'Test Noodle House')]));
    await _searchFor(tester, 'ramen');
    expect(find.textContaining('Photo:'), findsNothing);
    expect(find.text('Google Maps'), findsOneWidget);
  });

  test('prices: 0 is Free, 1–4 are dollar signs, anything else is hidden', () {
    expect(priceLabel(0), 'Free');
    expect(priceLabel(1), r'$');
    expect(priceLabel(4), r'$$$$');
    expect(priceLabel(null), isNull);
    expect(priceLabel(5), isNull);
  });

  test('Yes opens directions to the exact place, not a name search', () {
    final uri = directionsUri(_place('fake-place-1', 'Test Noodle House'))!;
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['destination'], '10.001,20.001');
    expect(uri.queryParameters['destination_place_id'], 'fake-place-1');
    expect(uri.toString(), isNot(contains('Noodle')));
    expect(directionsUri(const Restaurant(placeId: 'x', name: 'No Coordinates')), isNull);
  });
}

/// Device location near 10,20; any typed place is somewhere else.
class _MovableLocation extends LocationService {
  const _MovableLocation();
  @override
  Future<LocationResult> current() async => const LocationResult.found(_nearby);
  @override
  Future<SearchLocation?> lookUp(String place) async =>
      SearchLocation(latitude: 30, longitude: 40, label: place.trim());
}

/// Device location near 10,20; a typed place resolves only when the test says.
class _SlowLookup extends LocationService {
  const _SlowLookup(this.lookup);
  final Completer<SearchLocation?> lookup;
  @override
  Future<LocationResult> current() async => const LocationResult.found(_nearby);
  @override
  Future<SearchLocation?> lookUp(String place) => lookup.future;
}

/// Scrolls a button into view before tapping it, as a user would.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
