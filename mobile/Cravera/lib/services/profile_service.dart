import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in person's own settings, from their `profiles` row.
class Profile {
  const Profile({
    required this.displayName,
    this.homeCity,
    this.dietaryPreferences = const [],
    this.defaultRadiusMeters = Profile.defaultRadius,
  });

  final String displayName;
  final String? homeCity;
  final List<String> dietaryPreferences;
  final int defaultRadiusMeters;

  /// Same limits as the `profiles` table checks.
  static const maxNameLength = 60;
  static const maxCityLength = 80;
  static const defaultRadius = 5000;

  /// The choices the app offers. Stored as these exact strings.
  static const dietaryChoices = [
    'vegetarian',
    'vegan',
    'gluten-free',
    'dairy-free',
    'nut-free',
    'halal',
    'kosher',
    'no pork',
    'no shellfish',
  ];

  /// Default search distances the app offers, in meters.
  static const radiusChoices = [1000, 2000, 5000, 10000];

  Profile copyWith({String? displayName, String? homeCity, bool clearHomeCity = false, List<String>? dietaryPreferences, int? defaultRadiusMeters}) =>
      Profile(
        displayName: displayName ?? this.displayName,
        homeCity: clearHomeCity ? null : (homeCity ?? this.homeCity),
        dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
        defaultRadiusMeters: defaultRadiusMeters ?? this.defaultRadiusMeters,
      );

  /// The profile with trimmed text, or null if it breaks a table rule.
  Profile? validated() {
    final name = displayName.trim();
    final city = homeCity?.trim();
    if (name.isEmpty || name.length > maxNameLength) return null;
    if (city != null && city.length > maxCityLength) return null;
    if (dietaryPreferences.any((d) => !dietaryChoices.contains(d))) return null;
    if (defaultRadiusMeters < 500 || defaultRadiusMeters > 20000) return null;
    return Profile(
      displayName: name,
      homeCity: (city == null || city.isEmpty) ? null : city,
      dietaryPreferences: [for (final d in dietaryChoices) if (dietaryPreferences.contains(d)) d],
      defaultRadiusMeters: defaultRadiusMeters,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.displayName == displayName &&
      other.homeCity == homeCity &&
      other.defaultRadiusMeters == defaultRadiusMeters &&
      other.dietaryPreferences.join('|') == dietaryPreferences.join('|');

  @override
  int get hashCode => Object.hash(displayName, homeCity, defaultRadiusMeters, dietaryPreferences.join('|'));
}

enum ProfileSaveOutcome { ok, invalid, network, failed }

/// A plain sentence for each save outcome.
String profileSaveMessage(ProfileSaveOutcome outcome) => switch (outcome) {
      ProfileSaveOutcome.ok => 'Saved.',
      ProfileSaveOutcome.invalid => 'Names need 1 to 60 characters, and a home city up to 80.',
      ProfileSaveOutcome.network => 'Couldn’t save: no connection. Your old setting is kept.',
      ProfileSaveOutcome.failed => 'Couldn’t save right now. Your old setting is kept.',
    };

/// Reads and writes the signed-in person's own profile. Screens go through the
/// session, never Supabase directly, so tests can swap in a fake.
abstract class ProfileService {
  /// The profile of [userId], or null if it can't be read.
  Future<Profile?> load(String userId);

  /// Saves [profile] to [userId]'s row. RLS lets a person update only their
  /// own row, so if another account is signed in by then nothing is written.
  Future<ProfileSaveOutcome> save(String userId, Profile profile);
}

class SupabaseProfileService implements ProfileService {
  SupabaseProfileService(this._client);
  final SupabaseClient _client;

  static const _columns = 'display_name, home_city, dietary_preferences, default_radius_m';

  @override
  Future<Profile?> load(String userId) async {
    try {
      final row = await _client.from('profiles').select(_columns).eq('id', userId).maybeSingle();
      if (row == null) return null;
      final name = row['display_name'];
      final city = row['home_city'];
      final diet = row['dietary_preferences'];
      final radius = row['default_radius_m'];
      if (name is! String) return null;
      return Profile(
        displayName: name,
        homeCity: city is String ? city : null,
        // Keep only choices this app knows, so a save can't fail on old values.
        dietaryPreferences: diet is List ? [for (final d in diet) if (d is String && Profile.dietaryChoices.contains(d)) d] : const [],
        defaultRadiusMeters: radius is int ? radius : Profile.defaultRadius,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ProfileSaveOutcome> save(String userId, Profile profile) async {
    final valid = profile.validated();
    if (valid == null) return ProfileSaveOutcome.invalid;
    try {
      // Only the four columns the app may update (the table grants just these).
      final rows = await _client
          .from('profiles')
          .update({
            'display_name': valid.displayName,
            'home_city': valid.homeCity,
            'dietary_preferences': valid.dietaryPreferences,
            'default_radius_m': valid.defaultRadiusMeters,
          })
          .eq('id', userId)
          .select('id');
      // No row back: not this person's row (RLS) or it no longer exists.
      return rows.isEmpty ? ProfileSaveOutcome.failed : ProfileSaveOutcome.ok;
    } on SocketException {
      return ProfileSaveOutcome.network;
    } on TimeoutException {
      return ProfileSaveOutcome.network;
    } on ClientException {
      return ProfileSaveOutcome.network;
    } catch (_) {
      return ProfileSaveOutcome.failed;
    }
  }
}
