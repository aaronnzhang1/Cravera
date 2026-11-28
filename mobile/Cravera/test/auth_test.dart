// Accounts (TASK-003): screens and session with a fake auth service.
// Fictional data only; nothing calls Supabase.
import 'dart:async';

import 'package:cravera/core/session.dart';
import 'package:cravera/services/craving_search.dart';
import 'package:cravera/services/location_service.dart';
import 'package:cravera/main.dart';
import 'package:cravera/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthRetryableFetchException;

import 'craving_search_test.dart' show FakePlaces;
import 'location_test.dart' show FakeLocationService;

/// One fictional account; sign-up answers [signUpAnswer].
class FakeAuth implements AuthService {
  FakeAuth({this.signUpAnswer = AuthOutcome.confirmEmail, this.deleteAnswer = AuthOutcome.ok});

  static const knownEmail = 'tester@example.test';
  static const knownPassword = 'correct-horse-1';

  final AuthOutcome signUpAnswer;
  final AuthOutcome deleteAnswer;
  final _changes = StreamController<bool>.broadcast();
  bool _signedIn = false;
  String? _email;
  String? _name;
  int deleteCalls = 0;
  int signOutCalls = 0;
  final signUps = <(String, String)>[];

  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get email => _signedIn ? _email : null;
  @override
  String? get userId => _signedIn ? 'fake-user-${_email ?? 'x'}' : null;

  /// When set, the profile lookup waits for it (a slow network).
  Completer<String?>? nameGate;
  @override
  Stream<bool> get signedInChanges => _changes.stream;

  void _set(bool signedIn) {
    _signedIn = signedIn;
    _changes.add(signedIn);
  }

  /// The server ending the session (expired or revoked elsewhere).
  void expire() => _set(false);

  /// Another account replacing this one's session directly (no sign-out first).
  void switchTo(String otherEmail) {
    _email = otherEmail;
    _name = 'Other Diner';
    _set(true);
  }

  /// Accounts whose delete was asked for.
  final deleted = <String>[];

  @override
  Future<AuthOutcome> signIn({required String email, required String password}) async {
    if (email.trim() != knownEmail || password != knownPassword) return AuthOutcome.invalidCredentials;
    _email = knownEmail;
    _name ??= 'Test Diner';
    _set(true);
    return AuthOutcome.ok;
  }

  @override
  Future<AuthOutcome> signUp({required String email, required String password, required String displayName}) async {
    signUps.add((email, displayName));
    if (signUpAnswer == AuthOutcome.ok) {
      _email = email;
      _name = displayName;
      _set(true);
    }
    return signUpAnswer;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _set(false);
  }

  @override
  Future<String?> displayName() async {
    final gate = nameGate;
    if (gate != null) return gate.future;
    return _signedIn ? _name : null;
  }

  @override
  Future<AuthOutcome> deleteAccount({required String expectedUserId}) async {
    deleteCalls++;
    if (userId != expectedUserId) return AuthOutcome.failed;
    deleted.add(expectedUserId);
    if (deleteAnswer == AuthOutcome.ok) _set(false);
    return deleteAnswer;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _start(WidgetTester tester, AppSession session) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 915);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MyApp(session: session));
  await tester.pump();
}

Future<void> _signIn(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
  await tester.enterText(find.widgetWithText(TextField, 'Password'), password);
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await _settle(tester);
}

void main() {
  testWidgets('the right email and password open Home; the wrong ones say so and stay', (tester) async {
    final auth = FakeAuth();
    final session = AppSession(auth: auth);
    await _start(tester, session);

    await _signIn(tester, FakeAuth.knownEmail, 'wrong-password');
    expect(find.text(authMessage(AuthOutcome.invalidCredentials)), findsOneWidget);
    expect(session.isSignedIn, isFalse);
    expect(find.text('What are you craving?'), findsNothing);

    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    expect(session.isSignedIn, isTrue);
    expect(session.displayName, 'Test Diner', reason: 'name comes from the profile');
    expect(find.text('What are you craving?'), findsOneWidget);
  });

  testWidgets('sign-up sends the name and asks to confirm the email', (tester) async {
    final auth = FakeAuth();
    await _start(tester, AppSession(auth: auth));
    await tester.tap(find.text('Don’t have an account? Sign up'));
    await _settle(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Test Diner');
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'new-tester@example.test');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'long-enough-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await _settle(tester);

    expect(auth.signUps, [('new-tester@example.test', 'Test Diner')]);
    expect(find.text(authMessage(AuthOutcome.confirmEmail)), findsOneWidget);
    expect(find.text('Account'), findsNothing, reason: 'no separate username field');
    await tester.tap(find.text('Go to sign in'));
    await _settle(tester);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('delete account asks first; Cancel keeps it, Delete removes it and signs out', (tester) async {
    final auth = FakeAuth();
    final session = AppSession(auth: auth);
    await _start(tester, session);
    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    await tester.tap(find.text('Profile'));
    await _settle(tester);
    expect(find.text(FakeAuth.knownEmail), findsOneWidget, reason: 'Profile shows the account email');

    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await _settle(tester);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(auth.deleteCalls, 0);
    expect(session.isSignedIn, isTrue);

    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await _settle(tester);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(auth.deleteCalls, 1);
    expect(session.isSignedIn, isFalse);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('if another account takes over while the delete dialog is open, Delete does nothing', (tester) async {
    final auth = FakeAuth();
    final session = AppSession(auth: auth);
    await _start(tester, session);
    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    await tester.tap(find.text('Profile'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await _settle(tester);

    auth.switchTo('other-tester@example.test'); // B replaces A while A's dialog is open
    await _settle(tester);
    if (find.text('Delete').evaluate().isNotEmpty) {
      await tester.tap(find.text('Delete'));
      await _settle(tester);
    }
    expect(auth.deleted, isEmpty, reason: 'B is never deleted by the confirmation A opened');
    expect(auth.isSignedIn, isTrue);
  });

  testWidgets('a craving typed by one account is gone when another account takes over', (tester) async {
    final auth = FakeAuth();
    final session = AppSession(auth: auth);
    await _start(tester, session);
    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    await tester.enterText(find.widgetWithText(TextField, 'Ask Cravera…'), 'a private craving');
    await tester.pump();

    auth.switchTo('other-tester@example.test');
    await _settle(tester);
    expect(find.text('a private craving'), findsNothing);
  });

  testWidgets('a place dialog open across an account switch closes and searches nothing', (tester) async {
    final auth = FakeAuth();
    final places = FakePlaces((_) => []);
    final session = AppSession(
      auth: auth,
      locationService: FakeLocationService(const LocationResult.failed(LocationProblem.denied)),
      search: CravingSearch(places: places),
    );
    await _start(tester, session);
    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    await tester.enterText(find.widgetWithText(TextField, 'Ask Cravera…'), 'a private craving');
    await tester.tap(find.byTooltip('Search'));
    await _settle(tester);
    expect(find.text('Where should I search?'), findsOneWidget);

    auth.switchTo('other-tester@example.test');
    await _settle(tester);
    expect(find.text('Where should I search?'), findsNothing, reason: 'the old dialog is closed');
    expect(places.queries, isEmpty, reason: 'no search with the craving the previous person typed');
    expect(session.searchLocation, isNull);
  });

  testWidgets('a failed delete keeps the account and says so', (tester) async {
    final auth = FakeAuth(deleteAnswer: AuthOutcome.network);
    final session = AppSession(auth: auth);
    await _start(tester, session);
    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    await tester.tap(find.text('Profile'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await _settle(tester);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(session.isSignedIn, isTrue);
    expect(find.text(authMessage(AuthOutcome.network)), findsOneWidget);
  });

  testWidgets('when the session ends on the server, this device forgets the person', (tester) async {
    final auth = FakeAuth();
    final session = AppSession(auth: auth);
    await _start(tester, session);
    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    session.toggleBookmark(session.suggestedRestaurants.first);
    expect(session.bookmarks, isNotEmpty);

    auth.expire();
    await _settle(tester);
    expect(session.isSignedIn, isFalse);
    expect(session.bookmarks, isEmpty, reason: 'the next person on this phone sees nothing of theirs');
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('without accounts configured, sign-in fails politely and guest mode still works', (tester) async {
    final session = AppSession();
    await _start(tester, session);
    await _signIn(tester, FakeAuth.knownEmail, FakeAuth.knownPassword);
    expect(find.text(authMessage(AuthOutcome.failed)), findsOneWidget);

    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);
    expect(find.text('What are you craving?'), findsOneWidget);
    expect(session.isGuest, isTrue);
  });

  test('a session that ends while its name is still loading still clears local data', () async {
    final auth = FakeAuth()..nameGate = Completer<String?>();
    final session = AppSession(auth: auth);
    expect(await session.signInWithEmail(email: FakeAuth.knownEmail, password: FakeAuth.knownPassword), AuthOutcome.ok);
    session.toggleBookmark(session.suggestedRestaurants.first);

    auth.expire(); // before the profile lookup answers
    await pumpEventQueue();
    expect(session.isSignedIn, isFalse);
    expect(session.bookmarks, isEmpty, reason: 'cleared even though no name had loaded');

    auth.nameGate!.complete('Old Session Name');
    await pumpEventQueue();
    expect(session.displayName, isNot('Old Session Name'), reason: 'a late answer from the old session is dropped');
  });

  test('a delete can only target the account it was confirmed for', () async {
    final auth = FakeAuth();
    final session = AppSession(auth: auth);
    await session.signInWithEmail(email: FakeAuth.knownEmail, password: FakeAuth.knownPassword);
    final confirmedFor = session.accountId!;
    auth.switchTo('other-tester@example.test');
    await pumpEventQueue();
    expect(await session.deleteAccount(expectedAccountId: confirmedFor), AuthOutcome.failed);
    expect(auth.deleted, isEmpty);
    expect(session.isSignedIn, isTrue, reason: 'B stays signed in');
  });

  group('delete: an unclear answer is settled by asking whether the account still exists', () {
    Future<(AuthOutcome, int)> run({required Future<bool> Function() delete, required bool? exists}) async {
      var signedOut = 0;
      final outcome = await SupabaseAuthService.reconcileDelete(
        deleteOnServer: delete,
        accountStillExists: () async => exists,
        signOutLocally: () async => signedOut++,
      );
      return (outcome, signedOut);
    }

    test('confirmed delete signs out', () async {
      expect(await run(delete: () async => true, exists: true), (AuthOutcome.ok, 1));
    });
    test('answer lost, account gone: counts as deleted and signs out', () async {
      expect(await run(delete: () async => throw TimeoutException('lost'), exists: false), (AuthOutcome.ok, 1));
      expect(await run(delete: () async => false, exists: false), (AuthOutcome.ok, 1));
    });
    test('answer lost, account still there or unknown: reports the failure, stays signed in', () async {
      expect(await run(delete: () async => throw TimeoutException('lost'), exists: true), (AuthOutcome.network, 0));
      expect(await run(delete: () async => throw TimeoutException('lost'), exists: null), (AuthOutcome.network, 0));
      expect(await run(delete: () async => false, exists: null), (AuthOutcome.failed, 0));
    });
  });

  test('Supabase errors map to outcomes by code, never by message text', () {
    AuthOutcome map(Object e) => SupabaseAuthService.outcomeFor(e);
    expect(map(const AuthException('x', code: 'invalid_credentials')), AuthOutcome.invalidCredentials);
    expect(map(const AuthException('x', code: 'email_not_confirmed')), AuthOutcome.emailNotConfirmed);
    expect(map(const AuthException('x', code: 'user_already_exists')), AuthOutcome.emailInUse);
    expect(map(const AuthException('x', code: 'weak_password')), AuthOutcome.weakPassword);
    expect(map(const AuthException('x', code: 'over_email_send_rate_limit')), AuthOutcome.tooManyRequests);
    expect(map(const AuthException('invalid_credentials', code: 'something_new')), AuthOutcome.failed);
    expect(map(AuthRetryableFetchException()), AuthOutcome.network);
    // A 5xx answer is the server's problem, not the guest's connection.
    expect(map(AuthRetryableFetchException(statusCode: '500')), AuthOutcome.server);
    expect(map(AuthRetryableFetchException(statusCode: '503')), AuthOutcome.server);
    expect(authMessage(AuthOutcome.server), isNot(contains('connection')));
    expect(map(TimeoutException('slow')), AuthOutcome.network);
    expect(map(StateError('?')), AuthOutcome.failed);
  });
}
