import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cravio/core/session.dart';
import 'package:cravio/main.dart';
import 'package:cravio/services/location_service.dart';

/// Stands in for GPS and the geocoder. Places it knows are fictional.
class FakeLocationService extends LocationService {
  FakeLocationService(this.deviceResult);

  LocationResult deviceResult;
  int deviceCalls = 0;

  @override
  Future<LocationResult> current() async {
    deviceCalls++;
    return deviceResult;
  }

  @override
  Future<SearchLocation?> lookUp(String place) async {
    if (place.trim() == 'Nowhere Lane') return null;
    return SearchLocation(latitude: 1, longitude: 2, label: place.trim());
  }
}

const _nearby = SearchLocation(latitude: 10, longitude: 20, label: 'Near you');

Future<void> _enterAsGuest(WidgetTester tester, AppSession session) async {
  await tester.pumpWidget(MyApp(session: session));
  await tester.pump();
  await tester.tap(find.text('Continue as guest'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The logo animates forever, so pumpAndSettle never finishes. Step time instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('home asks for device location and shows it', (tester) async {
    final fake = FakeLocationService(const LocationResult.found(_nearby));
    final session = AppSession(locationService: fake);

    await _enterAsGuest(tester, session);
    await tester.pump();

    expect(fake.deviceCalls, 1);
    expect(session.searchLocation?.label, 'Near you');
    expect(find.text('Searching: Near you'), findsOneWidget);
  });

  testWidgets('denied location falls back to a typed place', (tester) async {
    final fake = FakeLocationService(const LocationResult.failed(LocationProblem.denied));
    final session = AppSession(locationService: fake);

    await _enterAsGuest(tester, session);
    await tester.pump();

    expect(session.searchLocation, isNull);
    expect(find.textContaining('Location permission was denied.'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, '1 Example Street');
    await tester.tap(find.text('Search here'));
    await _settle(tester);

    expect(session.searchLocation?.label, '1 Example Street');
    expect(find.text('Searching: 1 Example Street'), findsOneWidget);
  });

  testWidgets('an unknown typed place keeps no location and says so', (tester) async {
    final fake = FakeLocationService(const LocationResult.failed(LocationProblem.failed));
    final session = AppSession(locationService: fake);

    await _enterAsGuest(tester, session);
    await tester.pump();

    await tester.tap(find.text('Change'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Nowhere Lane');
    await tester.tap(find.text('Search here'));
    await _settle(tester);

    expect(session.searchLocation, isNull);
    expect(find.textContaining("Couldn't find 'Nowhere Lane'"), findsOneWidget);
  });

  testWidgets('searching with no location asks for a place first', (tester) async {
    final fake = FakeLocationService(const LocationResult.failed(LocationProblem.denied));
    final session = AppSession(locationService: fake);

    await _enterAsGuest(tester, session);
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'Type your craving…'), 'ramen');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await _settle(tester);

    expect(find.text('Where should I search?'), findsOneWidget);
  });

  testWidgets('a failed "Use my location" says so and keeps the typed place', (tester) async {
    final fake = FakeLocationService(const LocationResult.failed(LocationProblem.denied));
    final session = AppSession(locationService: fake);

    await _enterAsGuest(tester, session);
    await tester.pump();
    await session.useTypedPlace('1 Example Street');
    await _settle(tester);

    fake.deviceResult = const LocationResult.failed(LocationProblem.failed);
    await tester.tap(find.text('Change'));
    await _settle(tester);
    await tester.tap(find.text('Use my location'));
    await _settle(tester);

    expect(session.searchLocation?.label, '1 Example Street');
    expect(find.textContaining('Still searching: 1 Example Street'), findsOneWidget);
  });

  test('sign out forgets the location', () async {
    final session = AppSession(
      locationService: FakeLocationService(const LocationResult.found(_nearby)),
    );
    session.continueAsGuest();
    await session.useDeviceLocation();
    expect(session.searchLocation, isNotNull);

    session.signOut();
    expect(session.searchLocation, isNull);
    expect(session.locationProblem, isNull);
  });
}
