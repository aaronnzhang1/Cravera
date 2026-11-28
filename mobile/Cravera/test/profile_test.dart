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

/// Profiles kept in memory, per account, like the table: a save changes only
/// the columns it sends and returns the whole stored row. Loads and saves can
/// be made to fail or wait.
class FakeProfiles implements ProfileService {
  final rows = <String, Profile>{};
  ProfileSaveOutcome saveAnswer = ProfileSaveOutcome.ok;
  bool loadFails = false;
  Completer<void>? saveGate;
  Completer<void>? loadGate;
  final saves = <(String, Map<String, Object?>)>[];

  Profile _row(String userId) => rows[userId] ?? const Profile(displayName: 'Test Diner');

  @override
  Future<Profile?> load(String userId) async {
    await loadGate?.future;
    return loadFails ? null : _row(userId);
  }

  @override
  Future<(ProfileSaveOutcome, Profile?)> save(String userId, ProfileChange change) async {
    final columns = change.toColumns();
    if (columns == null) return (ProfileSaveOutcome.invalid, null);
    saves.add((userId, columns));
    await saveGate?.future;
    if (saveAnswer != ProfileSaveOutcome.ok) return (saveAnswer, null);
    final old = _row(userId);
    final stored = Profile(
      displayName: columns.containsKey('display_name') ? columns['display_name']! as String : old.displayName,
      homeCity: columns.containsKey('home_city') ? columns['home_city'] as String? : old.homeCity,
      dietaryPreferences: columns.containsKey('dietary_preferences') ? columns['dietary_preferences']! as List<String> : old.dietaryPreferences,
      defaultRadiusMeters: columns.containsKey('default_radius_m') ? columns['default_radius_m']! as int : old.defaultRadiusMeters,
    );
    rows[userId] = stored;
    return (ProfileSaveOutcome.ok, stored);
  }
}

const _me = 'fake-user-${FakeAuth.knownEmail}';

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
    profiles.rows[_me] = const Profile(displayName: 'Robin', homeCity: 'Oakland', dietaryPreferences: ['vegan'], defaultRadiusMeters: 2000);
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
    profiles.rows[_me] = const Profile(displayName: 'Robin', defaultRadiusMeters: 1000);
    await signIn();
    await session.search.start('tacos', near);
    await session.search.refine('cheaper');
    session.signOut();
    session.continueAsGuest();
    await session.search.start('tacos', near);
    expect(places.radii, [1000, 1000, null]);
  });

  test('profileReady waits for the profile, so the first search uses its distance', () async {
    profiles.rows[_me] = const Profile(displayName: 'Robin', defaultRadiusMeters: 1000);
    profiles.loadGate = Completer<void>();
    await session.signInWithEmail(email: FakeAuth.knownEmail, password: FakeAuth.knownPassword);
    var ready = false;
    unawaited(session.profileReady.then((_) => ready = true));
    await pumpEventQueue();
    expect(ready, isFalse, reason: 'still loading');
    expect(session.search.radiusMeters, isNull);
    profiles.loadGate!.complete();
    await session.profileReady;
    expect(session.search.radiusMeters, 1000);
  });

  testWidgets('a profile load that never answers does not hold search forever', (tester) async {
    // Widget tests run on a fake clock, so the 5 s wait passes instantly.
    profiles.loadGate = Completer<void>(); // never completes
    await session.signInWithEmail(email: FakeAuth.knownEmail, password: FakeAuth.knownPassword);
    var ready = false;
    unawaited(session.profileReady.then((_) => ready = true));
    await tester.pump(AppSession.profileWait - const Duration(milliseconds: 1));
    expect(ready, isFalse);
    await tester.pump(const Duration(milliseconds: 2));
    expect(ready, isTrue);
    expect(session.search.radiusMeters, isNull, reason: 'the server default is used');
  });

  test('a saved change is kept and comes back on the next sign-in', () async {
    await signIn();
    expect(await session.updateProfile(const ProfileChange(displayName: '  Sam  ')), ProfileSaveOutcome.ok);
    expect(await session.updateProfile(const ProfileChange(dietaryPreferences: ['halal', 'vegetarian'])), ProfileSaveOutcome.ok);
    expect(await session.updateProfile(const ProfileChange(defaultRadiusMeters: 10000)), ProfileSaveOutcome.ok);
    expect(session.displayName, 'Sam');
    expect(session.search.radiusMeters, 10000);
    // Stored trimmed, with choices in the app's order.
    expect(profiles.rows[_me]?.dietaryPreferences, ['vegetarian', 'halal']);

    session.signOut();
    await signIn();
    expect(session.profile?.displayName, 'Sam');
    expect(session.profile?.defaultRadiusMeters, 10000);
  });

  test('a save sends only the edited field, so an older copy elsewhere is not written back', () async {
    await signIn();
    // Another phone changes the name after this one loaded the profile.
    profiles.rows[_me] = const Profile(displayName: 'Renamed Elsewhere');
    expect(await session.updateProfile(const ProfileChange(defaultRadiusMeters: 2000)), ProfileSaveOutcome.ok);
    expect(profiles.saves.single.$2, {'default_radius_m': 2000});
    expect(profiles.rows[_me]?.displayName, 'Renamed Elsewhere');
    // And this phone now shows the stored row, including the newer name.
    expect(session.profile?.displayName, 'Renamed Elsewhere');
  });

  test('two quick saves run in order, so the later choice wins on the server and on screen', () async {
    await signIn();
    profiles.saveGate = Completer<void>();
    final first = session.updateProfile(const ProfileChange(defaultRadiusMeters: 2000));
    final second = session.updateProfile(const ProfileChange(defaultRadiusMeters: 10000));
    await pumpEventQueue();
    expect(profiles.saves.length, 1, reason: 'the second waits for the first');
    profiles.saveGate!.complete();
    expect(await first, ProfileSaveOutcome.ok);
    expect(await second, ProfileSaveOutcome.ok);
    expect([for (final s in profiles.saves) s.$2['default_radius_m']], [2000, 10000]);
    expect(profiles.rows[_me]?.defaultRadiusMeters, 10000);
    expect(session.profile?.defaultRadiusMeters, 10000);
    expect(session.search.radiusMeters, 10000);
  });

  test('a failed save says so and keeps the old values', () async {
    await signIn();
    final before = session.profile;
    for (final answer in [ProfileSaveOutcome.network, ProfileSaveOutcome.failed]) {
      profiles.saveAnswer = answer;
      expect(await session.updateProfile(const ProfileChange(homeCity: 'Berkeley')), answer);
      expect(session.profile, before);
    }
    expect(profileSaveMessage(ProfileSaveOutcome.failed), contains('old setting is kept'));
  });

  test('a save whose answer was lost shows what was actually stored', () async {
    await signIn();
    // The row was updated, but the answer never arrived.
    profiles.saveAnswer = ProfileSaveOutcome.network;
    profiles.rows[_me] = const Profile(displayName: 'Test Diner', defaultRadiusMeters: 2000);
    expect(await session.updateProfile(const ProfileChange(defaultRadiusMeters: 2000)), ProfileSaveOutcome.network);
    expect(session.profile?.defaultRadiusMeters, 2000);
    expect(session.search.radiusMeters, 2000, reason: 'search uses what is stored');
  });

  test('a re-read that never answers after a lost save does not lock the editors', () async {
    // Real time: the re-read gives up after profileWait * 2 (10 s).
    await signIn();
    profiles.saveAnswer = ProfileSaveOutcome.network;
    profiles.loadGate = Completer<void>(); // the re-read never answers
    final pending = session.updateProfile(const ProfileChange(homeCity: 'Berkeley'));
    await pumpEventQueue();
    expect(session.profileSaving, isTrue);
    expect(await pending, ProfileSaveOutcome.network);
    expect(session.profileSaving, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a profile load that never answers ends in Try again, not Loading forever', () async {
    // Real time: the load gives up after profileWait (5 s).
    profiles.loadGate = Completer<void>(); // never completes
    await session.signInWithEmail(email: FakeAuth.knownEmail, password: FakeAuth.knownPassword);
    await Future<void>.delayed(AppSession.profileWait + const Duration(milliseconds: 200));
    expect(session.profileLoadFailed, isTrue);
    expect(session.profile, isNull);
    profiles.loadGate = null;
    await session.retryProfileLoad();
    expect(session.profile, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a save that never answers frees the editors and reads back what is stored', () async {
    // Real time: the save gives up after profileWait * 2 (10 s).
    await signIn();
    profiles.saveGate = Completer<void>(); // never answers
    final pending = session.updateProfile(const ProfileChange(homeCity: 'Berkeley'));
    await pumpEventQueue();
    expect(session.profileSaving, isTrue);
    expect(await pending, ProfileSaveOutcome.network);
    expect(session.profileSaving, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a save still pending from the previous account neither locks nor delays the next', () async {
    await signIn();
    final firstGate = Completer<void>();
    profiles.saveGate = firstGate;
    final pending = session.updateProfile(const ProfileChange(displayName: 'First Person'));
    await pumpEventQueue();
    expect(session.profileSaving, isTrue);
    auth.switchTo('other@example.test');
    await pumpEventQueue();
    expect(session.profileSaving, isFalse, reason: 'the new account can edit right away');
    profiles.saveGate = null;
    expect(await session.updateProfile(const ProfileChange(homeCity: 'Oakland')), ProfileSaveOutcome.ok);
    expect(session.profile?.homeCity, 'Oakland');
    // The old save finishing later changes nothing for the new account.
    firstGate.complete();
    await pending;
    expect(session.profileSaving, isFalse);
    expect(session.profile?.displayName, isNot('First Person'));
  });

  test('an invalid name is refused before anything is sent', () async {
    await signIn();
    expect(await session.updateProfile(const ProfileChange(displayName: '   ')), ProfileSaveOutcome.invalid);
    expect(await session.updateProfile(ProfileChange(displayName: 'x' * 61)), ProfileSaveOutcome.invalid);
    expect(profiles.saves, isEmpty);
  });

  test('a save still in flight when the account changes is not applied to the new account', () async {
    await signIn();
    profiles.saveGate = Completer<void>();
    final pending = session.updateProfile(const ProfileChange(displayName: 'First Person'));
    auth.switchTo('other@example.test');
    await pumpEventQueue();
    profiles.saveGate!.complete();
    expect(await pending, ProfileSaveOutcome.failed);
    // The save went to the first account's row only, and the new account's
    // profile on screen isn't replaced by it.
    expect(profiles.saves.single.$1, _me);
    expect(session.profile?.displayName, isNot('First Person'));
  });

  test('a failed profile load can be retried', () async {
    profiles.loadFails = true;
    await signIn();
    expect(session.profile, isNull);
    expect(session.profileLoadFailed, isTrue);
    profiles.loadFails = false;
    await session.retryProfileLoad();
    expect(session.profileLoadFailed, isFalse);
    expect(session.profile?.displayName, 'Test Diner');
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
    expect(await session.updateProfile(const ProfileChange(displayName: 'Guest')), ProfileSaveOutcome.failed);
    expect(profiles.saves, isEmpty);
  });

  profileScreenTests();

  test('a change is checked against the table rules', () {
    expect(const ProfileChange(homeCity: '  ').toColumns(), {'home_city': null});
    expect(ProfileChange(homeCity: 'c' * 81).toColumns(), isNull);
    expect(const ProfileChange(dietaryPreferences: ['raw meat only']).toColumns(), isNull);
    expect(const ProfileChange(defaultRadiusMeters: 50000).toColumns(), isNull);
    expect(const ProfileChange().toColumns(), isNull, reason: 'nothing to save');
    // Counted like Postgres char_length: 31 emoji are 31 characters (62 in UTF-16).
    expect(ProfileChange(displayName: '\u{1F35C}' * 31).toColumns(), isNotNull);
    expect(ProfileChange(displayName: '\u{1F35C}' * 61).toColumns(), isNull);
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
    await tester.ensureVisible(find.text('Help'));
    expect(find.text('Help'), findsOneWidget);
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
    // The sheet rebuilds (here: the screen changes size); the picks must stay.
    tester.view.physicalSize = const Size(412, 900);
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settle(tester);
    expect(session.profile?.dietaryPreferences, ['vegan', 'halal']);
  });

  testWidgets('an open editor or sheet closes when another account takes over', (tester) async {
    final profiles = FakeProfiles()..rows[_me] = const Profile(displayName: 'First Person', homeCity: 'Old Town');
    final session = await _openProfile(tester, profiles);
    final auth = session.auth! as FakeAuth;

    // The home-city editor (a dialog on the app's navigator) shows A's city.
    await tester.ensureVisible(find.text('Home city'));
    await tester.tap(find.text('Home city'));
    await _settle(tester);
    expect(find.widgetWithText(TextField, 'Old Town'), findsOneWidget);
    auth.switchTo('other@example.test');
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing, reason: 'A\'s city is no longer on screen');
    expect(find.text('Old Town'), findsNothing);

    // The distance sheet (on the tabs' navigator) closes the same way.
    await tester.ensureVisible(find.text('Search distance'));
    await tester.tap(find.text('Search distance'));
    await _settle(tester);
    expect(find.text('10 km'), findsOneWidget);
    auth.switchTo('third@example.test');
    await _settle(tester);
    expect(find.text('10 km'), findsNothing);
    expect(profiles.saves, isEmpty, reason: 'nothing was saved by closing them');
  });

  testWidgets('an empty name says why it can\'t be saved', (tester) async {
    final profiles = FakeProfiles();
    await _openProfile(tester, profiles);
    await tester.tap(find.text('Name'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(find.text('Enter at least one character.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'stays open to fix it');
    expect(profiles.saves, isEmpty);
  });

  testWidgets('while a save is on its way, the editors stay closed', (tester) async {
    final profiles = FakeProfiles()..saveGate = Completer<void>();
    final session = await _openProfile(tester, profiles);
    await tester.ensureVisible(find.text('Dietary preferences'));
    await tester.tap(find.text('Dietary preferences'));
    await _settle(tester);
    await tester.tap(find.text('Vegan'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settle(tester);
    expect(session.profileSaving, isTrue);
    // Reopening now would start from the old list and could drop Vegan.
    await tester.tap(find.text('Dietary preferences'));
    await _settle(tester);
    expect(find.text('Halal'), findsNothing, reason: 'the sheet does not open mid-save');
    profiles.saveGate!.complete();
    await _settle(tester);
    expect(session.profileSaving, isFalse);
    expect(session.profile?.dietaryPreferences, ['vegan']);
    await tester.tap(find.text('Dietary preferences'));
    await _settle(tester);
    expect(find.text('Halal'), findsOneWidget, reason: 'open again once saved');
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
