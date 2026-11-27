import 'dart:async';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

/// What happened when the guest tried to sign up, sign in or delete their
/// account, in terms a screen can show.
enum AuthOutcome {
  ok,

  /// Signed up; Supabase sent a confirmation email and the account can be
  /// used after the link is opened.
  confirmEmail,
  invalidCredentials,
  emailNotConfirmed,
  emailInUse,
  weakPassword,
  invalidEmail,
  tooManyRequests,
  network,
  failed,
}

/// A plain sentence for each outcome (never the server's raw text).
String authMessage(AuthOutcome outcome) => switch (outcome) {
      AuthOutcome.ok => 'Done.',
      AuthOutcome.confirmEmail => 'Check your email and open the link to finish creating your account.',
      AuthOutcome.invalidCredentials => 'That email and password don’t match.',
      AuthOutcome.emailNotConfirmed => 'Open the link in the email we sent you first, then sign in.',
      AuthOutcome.emailInUse => 'There’s already an account with that email. Sign in instead.',
      AuthOutcome.weakPassword => 'Use a longer password (at least 8 characters).',
      AuthOutcome.invalidEmail => 'That doesn’t look like an email address.',
      AuthOutcome.tooManyRequests => 'Too many tries. Wait a few minutes and try again.',
      AuthOutcome.network => 'No connection. Check your internet and try again.',
      AuthOutcome.failed => 'Something went wrong. Try again.',
    };

/// Accounts (TASK-003). Screens use this, never Supabase directly, so tests
/// can swap in a fake and no auth logic lives in widgets.
abstract class AuthService {
  /// True while a signed-in session exists on this device.
  bool get isSignedIn;

  /// The signed-in person's email, for the Profile screen.
  String? get email;

  /// The signed-in account's ID (null when signed out). The session uses it
  /// to notice an account being lost or replaced; it is never sent anywhere.
  String? get userId;

  /// Fires when someone signs in or out (also when a stored session expires).
  Stream<bool> get signedInChanges;

  Future<AuthOutcome> signUp({required String email, required String password, required String displayName});
  Future<AuthOutcome> signIn({required String email, required String password});
  Future<void> signOut();

  /// The signed-in person's display name from their profile, or null.
  Future<String?> displayName();

  /// Deletes the signed-in person's own account on the server, then signs out.
  Future<AuthOutcome> deleteAccount();
}

/// The real service, on the Supabase client set up in `main.dart`.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);
  final SupabaseClient _client;

  /// Shortest password we ask for; Supabase's own minimum is set to match.
  static const minPasswordLength = 8;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  String? get email => _client.auth.currentUser?.email;

  @override
  String? get userId => _client.auth.currentSession?.user.id;

  @override
  Stream<bool> get signedInChanges => _client.auth.onAuthStateChange.map((s) => s.session != null);

  @override
  Future<AuthOutcome> signUp({required String email, required String password, required String displayName}) async {
    final local = _checkInput(email, password);
    if (local != null) return local;
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // The sign-up trigger copies this into the profile (trimmed, capped).
        data: {'display_name': displayName.trim()},
      );
      // With email confirmation on, there is a user but no session yet.
      return res.session == null ? AuthOutcome.confirmEmail : AuthOutcome.ok;
    } catch (e) {
      return outcomeFor(e);
    }
  }

  @override
  Future<AuthOutcome> signIn({required String email, required String password}) async {
    if (!_looksLikeEmail(email)) return AuthOutcome.invalidEmail;
    if (password.isEmpty) return AuthOutcome.invalidCredentials;
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
      return AuthOutcome.ok;
    } catch (e) {
      return outcomeFor(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Signing out locally still works when the network is down.
    }
  }

  @override
  Future<String?> displayName() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return null;
    try {
      // RLS returns only the caller's own row; the filter just narrows it.
      final row = await _client.from('profiles').select('display_name').eq('id', id).maybeSingle();
      final name = row?['display_name'];
      return name is String && name.trim().isNotEmpty ? name.trim() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthOutcome> deleteAccount() async {
    if (!isSignedIn) return AuthOutcome.failed;
    return reconcileDelete(
      // The function finds the account from the caller's own token; nothing
      // in the request names a user.
      deleteOnServer: () async =>
          (await _client.functions.invoke('delete-account', body: const <String, Object?>{})).status == 200,
      accountStillExists: _accountStillExists,
      signOutLocally: signOut,
    );
  }

  /// Whether this session's account still exists on the server: false only
  /// when Supabase says the user is gone (never for an expired token or a
  /// network error, which are null: unknown).
  Future<bool?> _accountStillExists() async {
    try {
      await _client.auth.getUser();
      return true;
    } on AuthException catch (e) {
      return e.code == 'user_not_found' ? false : null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes on the server, and settles an unclear answer: if the request
  /// failed or its answer was lost but the account is confirmed gone, the
  /// delete happened, so this device signs out too. Otherwise it reports the
  /// failure and keeps the person signed in.
  static Future<AuthOutcome> reconcileDelete({
    required Future<bool> Function() deleteOnServer,
    required Future<bool?> Function() accountStillExists,
    required Future<void> Function() signOutLocally,
  }) async {
    Object? error;
    try {
      if (await deleteOnServer()) {
        await signOutLocally();
        return AuthOutcome.ok;
      }
    } catch (e) {
      error = e;
    }
    if (await accountStillExists() == false) {
      await signOutLocally();
      return AuthOutcome.ok;
    }
    return error == null ? AuthOutcome.failed : outcomeFor(error);
  }

  static AuthOutcome? _checkInput(String email, String password) {
    if (!_looksLikeEmail(email)) return AuthOutcome.invalidEmail;
    if (password.length < minPasswordLength) return AuthOutcome.weakPassword;
    return null;
  }

  static bool _looksLikeEmail(String email) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

  /// Maps Supabase errors to outcomes by their stable codes, never by text.
  static AuthOutcome outcomeFor(Object error) {
    if (error is SocketException || error is TimeoutException || error is AuthRetryableFetchException) {
      return AuthOutcome.network;
    }
    if (error is AuthWeakPasswordException) return AuthOutcome.weakPassword;
    if (error is AuthException) {
      return switch (error.code) {
        'invalid_credentials' => AuthOutcome.invalidCredentials,
        'email_not_confirmed' => AuthOutcome.emailNotConfirmed,
        'user_already_exists' || 'email_exists' => AuthOutcome.emailInUse,
        'weak_password' => AuthOutcome.weakPassword,
        'email_address_invalid' || 'validation_failed' => AuthOutcome.invalidEmail,
        'over_request_rate_limit' || 'over_email_send_rate_limit' => AuthOutcome.tooManyRequests,
        _ => AuthOutcome.failed,
      };
    }
    return AuthOutcome.failed;
  }
}
