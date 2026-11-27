import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cravera/core/session.dart';
import 'package:cravera/main.dart';
import 'package:cravera/services/location_service.dart';

/// Always "found" at a fictional place, so no real location API is touched.
class _FixedLocation extends LocationService {
  @override
  Future<LocationResult> current() async =>
      const LocationResult.found(SearchLocation(latitude: 1, longitude: 2, label: 'Near you'));

  @override
  Future<SearchLocation?> lookUp(String place) async => SearchLocation(latitude: 3, longitude: 4, label: place);
}

Future<void> _enterAsGuest(WidgetTester tester, AppSession session) async {
  // A typical phone, so the sign-in buttons are on screen.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 915);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MyApp(session: session));
  await tester.pump();
  await tester.tap(find.text('Continue as guest'));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  layoutAcrossScreens();

  testWidgets('on a short phone with the keyboard open, the composer still fits', (tester) async {
    await _enterAsGuest(tester, AppSession(locationService: _FixedLocation()));

    // Then a 360 x 640 phone (iPhone SE class) with a 300-point keyboard open.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'no layout overflow');
    expect(find.widgetWithText(TextField, 'Ask Cravera…').hitTestable(), findsOneWidget);
    expect(find.text('What are you craving?'), findsNothing, reason: 'the hero steps aside while typing');
  });

  testWidgets('a guest who opens sign-up or sign-in keeps their session and place', (tester) async {
    final session = AppSession(locationService: _FixedLocation());
    await _enterAsGuest(tester, session);
    await session.useTypedPlace('1 Example Street');

    await tester.tap(find.text('Profile'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(find.text('Create account'));
    await tester.pump();
    await tester.tap(find.text('Create account'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Create your account'), findsOneWidget);
    expect(session.isGuest, isTrue);
    expect(session.searchLocation?.label, '1 Example Street');

    // And on to sign-in, still as the same guest.
    await tester.tap(find.text('Already have an account? Sign in'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Continue as guest'), findsOneWidget, reason: 'the sign-in screen opened');
    expect(session.isGuest, isTrue);
    expect(session.searchLocation?.label, '1 Example Street');
  });
}

/// Phones and a tablet, in logical points, with their safe-area insets:
/// iPhones have a notch or island at the top and a home indicator at the
/// bottom; Android phones a status bar and a gesture bar.
const _screens = <(String, Size, EdgeInsets)>[
  ('iPhone SE', Size(320, 568), EdgeInsets.only(top: 20)),
  ('iPhone 16', Size(393, 852), EdgeInsets.only(top: 59, bottom: 34)),
  ('Pixel 10 Pro', Size(412, 915), EdgeInsets.only(top: 40, bottom: 24)),
  ('small Android', Size(360, 640), EdgeInsets.only(top: 24, bottom: 48)),
  ('tablet', Size(820, 1180), EdgeInsets.only(top: 24, bottom: 20)),
];

void layoutAcrossScreens() {
  for (final (name, size, insets) in _screens) {
    testWidgets('Home on $name: location chip at the top right, nothing overflows', (tester) async {
      await _enterAsGuest(tester, AppSession(locationService: _FixedLocation()));
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = size * 2;
      tester.view.padding = FakeViewPadding(top: insets.top * 2, bottom: insets.bottom * 2);
      tester.view.viewPadding = FakeViewPadding(top: insets.top * 2, bottom: insets.bottom * 2);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull, reason: 'no overflow on $name');

      final chip = tester.getRect(find.byTooltip('Change location'));
      final title = tester.getRect(find.text('Cravera'));
      // Content is at most 520 wide, centred: the chip ends at that column's right edge (20 pt margin).
      final column = size.width > 520 ? (size.width - 520) / 2 + 520 : size.width;
      expect(chip.right, moreOrLessEquals(column - 20, epsilon: 1), reason: 'chip at the right edge on $name');
      expect(chip.top, greaterThanOrEqualTo(insets.top), reason: 'chip below the notch/status bar on $name');
      expect((chip.center.dy - title.center.dy).abs(), lessThan(4), reason: 'chip on the title line on $name');
    });
  }
}
