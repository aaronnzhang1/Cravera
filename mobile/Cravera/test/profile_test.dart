import 'dart:async';

import 'package:cravera/core/session.dart';
import 'package:cravera/services/craving_search.dart';
import 'package:cravera/services/location_service.dart';
import 'package:cravera/services/profile_service.dart';
import 'package:cravera/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show FakeAuth;
import 'craving_search_test.dart' show FakePlaces;

/// Profiles kept in memory, per account. Saves can be made to fail or wait.
class FakeProfiles implements ProfileService {
  final rows = <String, Profile>{};
  ProfileSaveOutcome saveAnswer = ProfileSaveOutcome.ok;
  Completer<void>? saveGate;
  final saves = <(String, Profile)>[];

  @override
  Future<Profile?> load(String userId) async => rows[userId] ?? const Profile(displayName: 'Test Diner');

  @override
  Future<ProfileSaveOutcome> save(String userId, Profile profile) async {
    saves.add((userId, profile));
    await saveGate?.future;
    if (saveAnswer == ProfileSaveOutcome.ok) rows[userId] = profile;
    return saveAnswer;
  }
}

void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late AppSession session;

  Future<void> signIn() async {
    await session.signInWithEmail(email: FakeAuth.knownEmail, password: FakeAuth.knownPassword);
    await pumpEventQueue();
  }

  setUp(() {
    auth = FakeAuth();
    profiles = FakeProfiles();
    session = AppSession(
      search: CravingSearch(places: FakePlaces((_) => [])),
      auth: auth,
      profiles: profiles,
    );
  });

  test('signing in loads the profile, and its default distance steers search', () async {
    profiles.rows['fake-user-${FakeAuth.knownEmail}'] =
        const Profile(displayName: 'Robin', homeCity: 'Oakland', dietaryPreferences: ['vegan'], defaultRadiusMeters: 2000);
    await signIn();
    expect(session.profile?.homeCity, 'Oakland');
    expect(session.displayName, 'Robin');
    expect(session.search.radiusMeters, 2000);
  });

  test('searches and refines send the default distance; guests send none', () async {
    final places = FakePlaces((_) => []);
    places.intent = {'textQuery': 'tacos'};
    session = AppSession(search: CravingSearch(places: places), auth: auth, profiles: profiles);
    const near = SearchLocation(latitude: 37.77, longitude: -122.42, label: 'Test City');
    profiles.rows['fake-user-${FakeAuth.knownEmail}'] = const Profile(displayName: 'Robin', defaultRadiusMeters: 1000);
    await signIn();
    await session.search.start('tacos', near);
    await session.search.refine('cheaper');
    session.signOut();
    session.continueAsGuest();
    await session.search.start('tacos', near);
    expect(places.radii, [1000, 1000, null]);
  });

  test('a saved change is kept and comes back on the next sign-in', () async {
    await signIn();
    final changed = session.profile!.copyWith(displayName: '  Sam  ', dietaryPreferences: ['halal', 'vegetarian'], defaultRadiusMeters: 10000);
    expect(await session.saveProfile(changed), ProfileSaveOutcome.ok);
    expect(session.displayName, 'Sam');
    expect(session.search.radiusMeters, 10000);
    // Stored trimmed, with choices in the app's order.
    expect(profiles.saves.single.$2.dietaryPreferences, ['vegetarian', 'halal']);

    session.signOut();
    await signIn();
    expect(session.profile?.displayName, 'Sam');
    expect(session.profile?.defaultRadiusMeters, 10000);
  });

  test('a failed save says so and keeps the old values', () async {
    await signIn();
    final before = session.profile;
    for (final answer in [ProfileSaveOutcome.network, ProfileSaveOutcome.failed]) {
      profiles.saveAnswer = answer;
      expect(await session.saveProfile(before!.copyWith(homeCity: 'Berkeley')), answer);
      expect(session.profile, before);
    }
    expect(profileSaveMessage(ProfileSaveOutcome.network), contains('old setting is kept'));
  });

  test('an invalid name is refused before anything is sent', () async {
    await signIn();
    expect(await session.saveProfile(session.profile!.copyWith(displayName: '   ')), ProfileSaveOutcome.invalid);
    expect(await session.saveProfile(session.profile!.copyWith(displayName: 'x' * 61)), ProfileSaveOutcome.invalid);
    expect(profiles.saves, isEmpty);
  });

  test('a save still in flight when the account changes is not applied to the new account', () async {
    await signIn();
    profiles.saveGate = Completer<void>();
    final pending = session.saveProfile(session.profile!.copyWith(displayName: 'First Person'));
    auth.switchTo('other@example.test');
    await pumpEventQueue();
    profiles.saveGate!.complete();
    expect(await pending, ProfileSaveOutcome.failed);
    // The save went to the first account's row only, and the new account's
    // profile on screen isn't replaced by it.
    expect(profiles.saves.single.$1, 'fake-user-${FakeAuth.knownEmail}');
    expect(session.profile?.displayName, isNot('First Person'));
  });

  test('signing out forgets the profile and the default distance', () async {
    await signIn();
    session.signOut();
    expect(session.profile, isNull);
    expect(session.search.radiusMeters, isNull);
  });

  test('guests have no profile and cannot save one', () async {
    session.continueAsGuest();
    expect(session.profile, isNull);
    expect(await session.saveProfile(const Profile(displayName: 'Guest')), ProfileSaveOutcome.failed);
    expect(profiles.saves, isEmpty);
  });

  profileScreenTests();

  test('validation matches the table rules', () {
    expect(const Profile(displayName: 'A', homeCity: '  ').validated()?.homeCity, isNull);
    expect(Profile(displayName: 'A', homeCity: 'c' * 81).validated(), isNull);
    expect(const Profile(displayName: 'A', dietaryPreferences: ['raw meat only']).validated(), isNull);
    expect(const Profile(displayName: 'A', defaultRadiusMeters: 50000).validated(), isNull);
  });
}

// --- the Profile screen ---

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the app on Profile, signed in (with [profiles]) or as a guest.
Future<AppSession> _openProfile(WidgetTester tester, FakeProfiles profiles, {bool guest = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 915);
  addTearDown(tester.view.reset);
  final session = AppSession(search: CravingSearch(places: FakePlaces((_) => [])), auth: FakeAuth(), profiles: profiles);
  await tester.pumpWidget(MyApp(session: session));
  await tester.pump();
  if (guest) {
    await tester.tap(find.text('Continue as guest'));
  } else {
    await tester.enterText(find.widgetWithText(TextField, 'Email'), FakeAuth.knownEmail);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), FakeAuth.knownPassword);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  }
  await _settle(tester);
  await tester.tap(find.text('Profile'));
  await _settle(tester);
  return session;
}

void profileScreenTests() {
  testWidgets('Profile is in sections with no "coming soon" rows', (tester) async {
    await _openProfile(tester, FakeProfiles());
    for (final label in ['ACCOUNT', 'PREFERENCES', 'ABOUT']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final gone in ['Notifications', 'Help & support', 'Location']) {
      expect(find.text(gone), findsNothing);
    }
    expect(find.text(FakeAuth.knownEmail), findsOneWidget);
    expect(find.text('5 km'), findsOneWidget, reason: 'the default distance shows');
  });

  testWidgets('editing the name saves it and shows it', (tester) async {
    final profiles = FakeProfiles();
    final session = await _openProfile(tester, profiles);
    await tester.tap(find.text('Name'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Robin');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await _settle(tester);
    expect(session.profile?.displayName, 'Robin');
    expect(find.text(profileSaveMessage(ProfileSaveOutcome.ok)), findsOneWidget);
  });

  testWidgets('choosing a distance saves it; a failed save says so and keeps the old one', (tester) async {
    final profiles = FakeProfiles();
    final session = await _openProfile(tester, profiles);
    await tester.ensureVisible(find.text('Search distance'));
    await tester.tap(find.text('Search distance'));
    await _settle(tester);
    await tester.tap(find.text('2 km'));
    await _settle(tester);
    expect(session.profile?.defaultRadiusMeters, 2000);

    profiles.saveAnswer = ProfileSaveOutcome.network;
    await tester.tap(find.text('Search distance'));
    await _settle(tester);
    await tester.tap(find.text('10 km'));
    await _settle(tester);
    expect(session.profile?.defaultRadiusMeters, 2000);
    expect(find.text(profileSaveMessage(ProfileSaveOutcome.network)), findsOneWidget);
  });

  testWidgets('dietary choices save as picked', (tester) async {
    final profiles = FakeProfiles();
    final session = await _openProfile(tester, profiles);
    await tester.ensureVisible(find.text('Dietary preferences'));
    await tester.tap(find.text('Dietary preferences'));
    await _settle(tester);
    await tester.tap(find.text('Vegan'));
    await tester.tap(find.text('Halal'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settle(tester);
    expect(session.profile?.dietaryPreferences, ['vegan', 'halal']);
  });

  testWidgets('a guest sees preferences off and an honest account prompt', (tester) async {
    final profiles = FakeProfiles();
    await _openProfile(tester, profiles, guest: true);
    expect(find.text('Create an account to save preferences.'), findsOneWidget);
    expect(find.textContaining('coming'), findsNothing);
    await tester.ensureVisible(find.text('Dietary preferences'));
    await tester.tap(find.text('Dietary preferences'));
    await _settle(tester);
    expect(find.text('Save'), findsNothing, reason: 'nothing opens for a guest');
    expect(profiles.saves, isEmpty);
  });
}
