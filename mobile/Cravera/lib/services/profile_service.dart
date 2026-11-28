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

/// One edit to a profile: only the fields set here are sent, so a save from
/// a phone with an older copy can't overwrite the other settings.
class ProfileChange {
  const ProfileChange({this.displayName, this.homeCity, this.dietaryPreferences, this.defaultRadiusMeters});

  final String? displayName;

  /// An empty string clears the home city.
  final String? homeCity;
  final List<String>? dietaryPreferences;
  final int? defaultRadiusMeters;

  /// The columns to update, checked against the table rules; null if a value
  /// breaks a rule or nothing is set.
  Map<String, Object?>? toColumns() {
    final out = <String, Object?>{};
    if (displayName != null) {
      final name = displayName!.trim();
      // runes: characters as Postgres char_length counts them (an emoji is one).
      if (name.isEmpty || name.runes.length > Profile.maxNameLength) return null;
      out['display_name'] = name;
    }
    if (homeCity != null) {
      final city = homeCity!.trim();
      if (city.runes.length > Profile.maxCityLength) return null;
      out['home_city'] = city.isEmpty ? null : city;
    }
    if (dietaryPreferences != null) {
      if (dietaryPreferences!.any((d) => !Profile.dietaryChoices.contains(d))) return null;
      out['dietary_preferences'] = [for (final d in Profile.dietaryChoices) if (dietaryPreferences!.contains(d)) d];
    }
    if (defaultRadiusMeters != null) {
      if (defaultRadiusMeters! < 500 || defaultRadiusMeters! > 20000) return null;
      out['default_radius_m'] = defaultRadiusMeters;
    }
    return out.isEmpty ? null : out;
  }
}

enum ProfileSaveOutcome { ok, invalid, network, failed }

/// A plain sentence for each save outcome.
String profileSaveMessage(ProfileSaveOutcome outcome) => switch (outcome) {
      ProfileSaveOutcome.ok => 'Saved.',
      ProfileSaveOutcome.invalid => 'Names need 1 to 60 characters, and a home city up to 80.',
      ProfileSaveOutcome.network => 'Couldn’t confirm the save: no connection. Showing your settings as last saved.',
      ProfileSaveOutcome.failed => 'Couldn’t save right now. Your old setting is kept.',
    };

/// Reads and writes the signed-in person's own profile. Screens go through the
/// session, never Supabase directly, so tests can swap in a fake.
abstract class ProfileService {
  /// The profile of [userId], or null if it can't be read.
  Future<Profile?> load(String userId);

  /// Saves [change] to [userId]'s row and returns the whole row as stored
  /// (null unless ok). RLS lets a person update only their own row, so if
  /// another account is signed in by then nothing is written.
  Future<(ProfileSaveOutcome, Profile?)> save(String userId, ProfileChange change);
}

class SupabaseProfileService implements ProfileService {
  SupabaseProfileService(this._client);
  final SupabaseClient _client;

  static const _columns = 'display_name, home_city, dietary_preferences, default_radius_m';

  /// A profile from a table row, or null if the row is unusable.
  static Profile? _fromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final name = row['display_name'];
    final city = row['home_city'];
    final diet = row['dietary_preferences'];
    final radius = row['default_radius_m'];
    if (name is! String) return null;
    return Profile(
      displayName: name,
      homeCity: city is String ? city : null,
      // Keep only choices this app knows.
      dietaryPreferences: diet is List ? [for (final d in diet) if (d is String && Profile.dietaryChoices.contains(d)) d] : const [],
      defaultRadiusMeters: radius is int ? radius : Profile.defaultRadius,
    );
  }

  @override
  Future<Profile?> load(String userId) async {
    try {
      return _fromRow(await _client.from('profiles').select(_columns).eq('id', userId).maybeSingle());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<(ProfileSaveOutcome, Profile?)> save(String userId, ProfileChange change) async {
    final columns = change.toColumns();
    if (columns == null) return (ProfileSaveOutcome.invalid, null);
    try {
      // Only the edited columns (the table grants update on just these four).
      final rows = await _client.from('profiles').update(columns).eq('id', userId).select(_columns);
      // No row back: not this person's row (RLS) or it no longer exists.
      final stored = rows.isEmpty ? null : _fromRow(rows.first);
      return stored == null ? (ProfileSaveOutcome.failed, null) : (ProfileSaveOutcome.ok, stored);
    } on SocketException {
      return (ProfileSaveOutcome.network, null);
    } on TimeoutException {
      return (ProfileSaveOutcome.network, null);
    } on ClientException {
      return (ProfileSaveOutcome.network, null);
    } catch (_) {
      return (ProfileSaveOutcome.failed, null);
    }
  }
}
