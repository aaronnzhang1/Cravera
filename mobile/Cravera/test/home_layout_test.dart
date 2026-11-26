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
  testWidgets('on a short phone with the keyboard open, the composer still fits', (tester) async {
    await _enterAsGuest(tester, AppSession(locationService: _FixedLocation()));

    // Then a 360 x 640 phone (iPhone SE class) with a 300-point keyboard open.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'no layout overflow');
    expect(find.widgetWithText(TextField, 'Ask Cravera…').hitTestable(), findsOneWidget);
    expect(find.text('What are you\ncraving today?'), findsNothing, reason: 'the hero steps aside while typing');
  });

  testWidgets('a guest who opens sign-up keeps their session and place', (tester) async {
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
  });
}
