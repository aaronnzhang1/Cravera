// Accounts (TASK-003): screens and session with a fake auth service.
// Fictional data only; nothing calls Supabase.
import 'dart:async';

import 'package:cravera/core/session.dart';
import 'package:cravera/main.dart';
import 'package:cravera/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthRetryableFetchException;

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
  Stream<bool> get signedInChanges => _changes.stream;

  void _set(bool signedIn) {
    _signedIn = signedIn;
    _changes.add(signedIn);
  }

  /// The server ending the session (expired or revoked elsewhere).
  void expire() => _set(false);

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
  Future<String?> displayName() async => _signedIn ? _name : null;

  @override
  Future<AuthOutcome> deleteAccount() async {
    deleteCalls++;
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

  test('Supabase errors map to outcomes by code, never by message text', () {
    AuthOutcome map(Object e) => SupabaseAuthService.outcomeFor(e);
    expect(map(const AuthException('x', code: 'invalid_credentials')), AuthOutcome.invalidCredentials);
    expect(map(const AuthException('x', code: 'email_not_confirmed')), AuthOutcome.emailNotConfirmed);
    expect(map(const AuthException('x', code: 'user_already_exists')), AuthOutcome.emailInUse);
    expect(map(const AuthException('x', code: 'weak_password')), AuthOutcome.weakPassword);
    expect(map(const AuthException('x', code: 'over_email_send_rate_limit')), AuthOutcome.tooManyRequests);
    expect(map(const AuthException('invalid_credentials', code: 'something_new')), AuthOutcome.failed);
    expect(map(AuthRetryableFetchException()), AuthOutcome.network);
    expect(map(TimeoutException('slow')), AuthOutcome.network);
    expect(map(StateError('?')), AuthOutcome.failed);
  });
}
