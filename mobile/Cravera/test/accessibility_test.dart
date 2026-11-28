// Accessibility pass (TASK-UI-2): Flutter's own guideline checks on the main
// screens. Fictional data only; the network and GPS are faked.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cravera/core/session.dart';
import 'package:cravera/main.dart';
import 'package:cravera/models/restaurant.dart';
import 'package:cravera/services/craving_search.dart';
import 'package:cravera/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show FakeAuth;
import 'craving_search_test.dart' show FakePlaces;
import 'profile_test.dart' show FakeProfiles;

const _nearby = SearchLocation(latitude: 10, longitude: 20, label: 'Near you');

class _FoundLocation extends LocationService {
  const _FoundLocation();
  @override
  Future<LocationResult> current() async => const LocationResult.found(_nearby);
}

const _pick = Restaurant(
  placeId: 'a',
  name: 'Test Noodle House',
  cuisine: 'Ramen Restaurant',
  address: '1 Example St, Testville',
  priceLevel: 2,
  rating: 4.5,
  distanceMeters: 150,
  photoName: 'places/a/photos/p',
  photoAuthors: [PhotoAuthor(name: 'Test Photographer', uri: 'https://maps.google.com/maps/contrib/fake')],
  photoMapsUri: 'https://www.google.com/maps/place//data=fake',
  latitude: 10.001,
  longitude: 20.001,
  reasons: ['Budget-friendly', 'Close by'],
);

/// A real, all-black 8 x 8 PNG: the darkest photo the controls can sit on.
final _blackPhoto = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAADElEQVR4nGNgGB4AAADIAAGtQHYiAAAAAElFTkSuQmCC');

Future<void> _settle(WidgetTester tester) async {
  // The orb animates forever, so pumpAndSettle never finishes. Step time instead.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _home(WidgetTester tester) async {
  final places = FakePlaces((_) => [_pick, _pick], photo: (_) => Uint8List.fromList(_blackPhoto));
  final session = AppSession(locationService: const _FoundLocation(), search: CravingSearch(places: places));
  await tester.pumpWidget(MyApp(session: session));
  await tester.pump();
  await tester.tap(find.text('Continue as guest'));
  await _settle(tester);
}

Future<void> _showPick(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Ask Cravera…'), 'ramen');
  await tester.tap(find.byTooltip('Search'));
  await _settle(tester);
  // Decode the photo for real, so contrast is checked over it, not the placeholder.
  final photo = find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage);
  if (photo.evaluate().isNotEmpty) {
    await tester.runAsync(() => precacheImage((tester.widget<Image>(photo.first)).image, tester.element(photo.first)));
    await _settle(tester);
  }
}

/// The black photo is on screen (decoded), not the placeholder icon.
void _expectPhotoShown(WidgetTester tester) {
  expect(find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage), findsOneWidget);
  expect(find.byIcon(Icons.restaurant_rounded), findsNothing, reason: 'placeholder hidden');
}

Future<void> _meetsAll(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Opens a tab ([tab]: 'Profile' or 'Friends'), signed in with a profile or as a guest.
Future<void> _tab(WidgetTester tester, String tab, {bool signedIn = false}) async {
  final session = AppSession(
    locationService: const _FoundLocation(),
    search: CravingSearch(places: FakePlaces((_) => [])),
    auth: signedIn ? FakeAuth() : null,
    profiles: signedIn ? FakeProfiles() : null,
  );
  await tester.pumpWidget(MyApp(session: session));
  await tester.pump();
  if (signedIn) {
    await tester.enterText(find.widgetWithText(TextField, 'Email'), FakeAuth.knownEmail);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), FakeAuth.knownPassword);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  } else {
    await tester.tap(find.text('Continue as guest'));
  }
  await _settle(tester);
  await tester.tap(find.text(tab));
  await _settle(tester);
}

/// Checks the page at the top, then scrolled to the end (the checks only see what's on screen).
Future<void> _meetsAllScrolled(WidgetTester tester) async {
  await _meetsAll(tester);
  await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
  await _settle(tester);
  await _meetsAll(tester);
}

void main() {
  testWidgets('sign-in screen meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final session = AppSession(locationService: const _FoundLocation(), search: CravingSearch(places: FakePlaces((_) => [])));
    await tester.pumpWidget(MyApp(session: session));
    await _settle(tester);
    await _meetsAll(tester);
    handle.dispose();
  });

  testWidgets('home meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _home(tester);
    await _meetsAll(tester);
    handle.dispose();
  });

  testWidgets('the pick meets the accessibility guidelines, over a black photo', (tester) async {
    final handle = tester.ensureSemantics();
    await _home(tester);
    await _showPick(tester);
    _expectPhotoShown(tester);
    await _meetsAll(tester);
    handle.dispose();
  });

  testWidgets('the nothing-matched chat meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final session = AppSession(
      locationService: const _FoundLocation(),
      search: CravingSearch(places: FakePlaces((_) => [])),
    );
    await tester.pumpWidget(MyApp(session: session));
    await tester.pump();
    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);
    await _showPick(tester);
    expect(find.textContaining('Nothing open matched'), findsOneWidget);
    await _meetsAll(tester);
    handle.dispose();
  });

  testWidgets('the Yes sheet meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _home(tester);
    await _showPick(tester);
    await tester.tap(find.text('Yes'));
    await _settle(tester);
    expect(find.text('Navigate there'), findsOneWidget);
    await _meetsAll(tester);
    handle.dispose();
  });

  testWidgets('home meets them with small system text (0.8x)', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _home(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 0.8;
    await _settle(tester);
    expect(tester.getSize(find.byTooltip('Change location')).height, greaterThanOrEqualTo(48));
    await _meetsAll(tester);
    handle.dispose();
  });

  testWidgets('at large text on a small phone the title keeps its size; the chip takes its own line', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _home(tester);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1136); // 320 x 568
    await _settle(tester);
    final normal = tester.getSize(find.text('Cravera')).height;
    // 1.6x: the largest size at which even the (very wide) test font fits "Cravera" on a 320 pt line.
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final title = tester.getRect(find.text('Cravera'));
    final chip = tester.getRect(find.byTooltip('Change location'));
    expect(title.height, greaterThan(normal * 1.5), reason: 'the title grows with the text setting');
    expect(chip.top, greaterThanOrEqualTo(title.bottom), reason: 'the chip moves below the title');
    expect(chip.right, moreOrLessEquals(320 - 20, epsilon: 1), reason: 'still at the right edge');
  });

  testWidgets('home meets them at 2x text on a small phone', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _home(tester);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1136); // 320 x 568
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    await _meetsAll(tester);
    handle.dispose();
  });

  testWidgets('the pick meets them at 2x text on a small phone', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _home(tester);
    await _showPick(tester);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1136); // 320 x 568
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'no overflow');    await _meetsAll(tester);
    handle.dispose();
  });
  for (final (tab, signedIn) in [('Profile', true), ('Profile', false), ('Friends', false)]) {
    testWidgets('$tab${signedIn ? ' (signed in)' : ' (guest)'} meets the accessibility guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await _tab(tester, tab, signedIn: signedIn);
      await _meetsAllScrolled(tester);
      handle.dispose();
    });

    testWidgets('$tab${signedIn ? ' (signed in)' : ' (guest)'} meets them at 2x text on a small phone', (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _tab(tester, tab, signedIn: signedIn);
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(640, 1136); // 320 x 568
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      await _meetsAllScrolled(tester);
      handle.dispose();
    });
  }
}
