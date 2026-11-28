import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/restaurant.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/craving_search.dart';
import '../services/location_service.dart';

class AppSession extends ChangeNotifier {
  AppSession({this.locationService = const LocationService(), CravingSearch? search, this.auth, this.profiles})
      : search = search ?? CravingSearch() {
    // Screens listen to the session, so pass search changes on.
    this.search.addListener(notifyListeners);
    // Follow sign-in changes from the server too (a stored session that
    // expires, or one restored when the app starts).
    _authChanges = auth?.signedInChanges.listen((_) => _syncAccount());
    _syncAccount(notify: false);
  }

  /// The account this session is showing; null for guests and signed out.
  /// Tracked on its own (not through the display name, which loads later),
  /// so losing or replacing an account always clears its local data.
  String? _accountId;

  /// Numbers display-name lookups: an answer for an older session is dropped.
  int _nameRequest = 0;

  /// Goes up whenever an account is lost or replaced on this device, so
  /// screens can drop anything the previous person typed or opened.
  int _accountGeneration = 0;
  int get accountGeneration => _accountGeneration;

  /// The signed-in account's ID (null for guests). Screens capture it before
  /// an account action, so the action can't land on a different account.
  String? get accountId => _accountId;

  /// Matches [_accountId] to the auth service: clears the previous account's
  /// data on this device when it was lost or replaced, then loads the new
  /// account's display name.
  void _syncAccount({bool notify = true}) {
    final service = auth;
    final id = (service != null && service.isSignedIn) ? service.userId : null;
    if (id == _accountId) return;
    final hadAccount = _accountId != null;
    _accountId = id;
    _nameRequest++;
    if (hadAccount) {
      _accountGeneration++;
      _clearUserData();
    }
    if (id != null) {
      _isGuest = false;
      unawaited(_loadDisplayName(id, _nameRequest));
    }
    if (notify) notifyListeners();
  }

  /// Accounts (TASK-003). Null when the app has no Supabase key: then only
  /// guest mode works. Tests pass a fake.
  final AuthService? auth;
  StreamSubscription<bool>? _authChanges;

  @override
  void dispose() {
    _authChanges?.cancel();
    super.dispose();
  }

  /// The signed-in person's settings (TASK-UI-3). Null when the app has no
  /// Supabase key. Tests pass a fake.
  final ProfileService? profiles;

  /// The signed-in person's profile, once loaded; null for guests.
  Profile? _profile;
  Profile? get profile => _profile;

  /// Loads the signed-in person's profile (or just the display name without a
  /// profile service); dropped if the account changed or signed out meanwhile.
  Future<void> _loadDisplayName(String accountId, int request) async {
    final loaded = await profiles?.load(accountId);
    final name = loaded?.displayName ?? await auth?.displayName();
    if (request != _nameRequest || _accountId != accountId) return;
    _profile = loaded;
    search.radiusMeters = loaded?.defaultRadiusMeters;
    _displayName = name ?? auth?.email?.split('@').first ?? 'there';
    notifyListeners();
  }

  /// Saves [updated] as the signed-in person's profile. Bound to the account
  /// signed in when it was called: if that changes before the answer, the
  /// answer is dropped (and RLS stops a write to another person's row).
  Future<ProfileSaveOutcome> saveProfile(Profile updated) async {
    final service = profiles;
    final account = _accountId;
    if (service == null || account == null || _profile == null) return ProfileSaveOutcome.failed;
    final valid = updated.validated();
    if (valid == null) return ProfileSaveOutcome.invalid;
    final generation = _accountGeneration;
    final outcome = await service.save(account, valid);
    if (outcome != ProfileSaveOutcome.ok || _accountId != account || _accountGeneration != generation) {
      return outcome == ProfileSaveOutcome.ok ? ProfileSaveOutcome.failed : outcome;
    }
    _profile = valid;
    _displayName = valid.displayName;
    search.radiusMeters = valid.defaultRadiusMeters;
    notifyListeners();
    return ProfileSaveOutcome.ok;
  }

  /// Finds where to search. Tests pass a fake.
  final LocationService locationService;

  /// The current craving search and its results. Tests pass one with a fake
  /// [PlacesService].
  final CravingSearch search;

  String? _displayName;
  SearchLocation? _searchLocation;
  LocationProblem? _locationProblem;
  bool _locating = false;

  /// Numbers each location request. Only the newest may write its result:
  /// an older GPS or typed lookup that finishes late is dropped, so it can't
  /// replace the user's newer choice, or hand a signed-out user's location
  /// to the next one. Sign out also bumps it.
  int _locationRequest = 0;
  final List<Restaurant> _bookmarks = [];
  final Map<String, int> _bookmarkRatings = {};

  final List<Restaurant> _suggested = const [
    Restaurant(
      placeId: 'demo_1',
      name: 'Cedar & Citrus',
      cuisine: 'Mediterranean',
      address: '123 Market St',
      rating: 4.6,
      priceLevel: 2,
      distanceMeters: 1200,
    ),
    Restaurant(
      placeId: 'demo_2',
      name: 'Nori House',
      cuisine: 'Sushi',
      address: '88 Pine Ave',
      rating: 4.7,
      priceLevel: 3,
      distanceMeters: 2400,
    ),
    Restaurant(
      placeId: 'demo_3',
      name: 'Torch & Tacos',
      cuisine: 'Mexican',
      address: '42 Sunset Blvd',
      rating: 4.4,
      priceLevel: 1,
      distanceMeters: 900,
    ),
    Restaurant(
      placeId: 'demo_4',
      name: 'Saffron Spoon',
      cuisine: 'Indian',
      address: '7 Oak Lane',
      rating: 4.5,
      priceLevel: 2,
      distanceMeters: 3100,
    ),
  ];

  bool _isGuest = false;

  /// Signed in to a real account (a session exists on this device).
  bool get isSignedIn => auth?.isSignedIn ?? false;

  /// The signed-in person's email, for Profile.
  String? get email => auth?.email;

  /// True when the user chose "Continue as guest": they can use the app but have no account.
  bool get isGuest => _isGuest && !isSignedIn;

  /// Whether the user may enter the app screens (signed in or browsing as a guest).
  bool get canEnterApp => isSignedIn || isGuest;
  String get displayName => (_displayName ?? '').trim().isEmpty ? 'there' : _displayName!.trim();

  List<Restaurant> get bookmarks => List.unmodifiable(_bookmarks);
  List<Restaurant> get suggestedRestaurants => List.unmodifiable(_suggested);
  int bookmarkRating(String placeId) => _bookmarkRatings[placeId] ?? 0;

  /// Where searches happen: the device location or a typed place. Null until found.
  SearchLocation? get searchLocation => _searchLocation;

  /// Why the device location failed, so the screen can explain it.
  LocationProblem? get locationProblem => _locationProblem;
  bool get isLocating => _locating;

  /// True while the search area may be about to change (device fix or typed
  /// place still being looked up). Searching and directions wait for it, so
  /// nothing runs against the area the user is leaving.
  bool get locationChanging => _locating || _lookingUpPlace;
  bool _lookingUpPlace = false;

  /// Uses the device location. On failure, keeps any typed place already set.
  Future<void> useDeviceLocation() async {
    if (_locating) return;
    final request = ++_locationRequest;
    _locating = true;
    // This replaces any typed lookup still running, whose stale answer won't
    // clear its own flag, so clear it here or search would stay blocked.
    _lookingUpPlace = false;
    notifyListeners();
    final result = await locationService.current();
    if (request != _locationRequest) return; // a newer choice or sign out won
    _locating = false;
    if (result.location != null) {
      _setSearchLocation(result.location!);
      _locationProblem = null;
    } else {
      _locationProblem = result.problem;
    }
    notifyListeners();
  }

  /// Looks up a typed place. Returns false if it could not be found.
  Future<bool> useTypedPlace(String place) async {
    final request = ++_locationRequest;
    // A typed place replaces any device lookup still running.
    if (_locating) {
      _locating = false;
      notifyListeners();
    }
    _lookingUpPlace = true;
    notifyListeners();
    final SearchLocation? found;
    try {
      found = await locationService.lookUp(place);
    } finally {
      // Only the newest lookup clears the flag; sign out clears it too.
      if (request == _locationRequest) _lookingUpPlace = false;
    }
    if (request != _locationRequest) return false; // a newer choice or sign out won
    if (found == null) {
      notifyListeners();
      return false;
    }
    _setSearchLocation(found);
    notifyListeners();
    return true;
  }

  /// Results belong to the area they were searched in: a new area drops the
  /// current search, including one still waiting for an answer.
  void _setSearchLocation(SearchLocation location) {
    final old = _searchLocation;
    _searchLocation = location;
    final moved = old == null || old.latitude != location.latitude || old.longitude != location.longitude;
    if (moved && search.status != SearchStatus.idle) search.reset();
  }

  /// Signs in with email and password. A guest's place and search are kept.
  Future<AuthOutcome> signInWithEmail({required String email, required String password}) async {
    final service = auth;
    if (service == null) return AuthOutcome.failed;
    final outcome = await service.signIn(email: email, password: password);
    if (outcome == AuthOutcome.ok) _syncAccount(notify: false);
    notifyListeners();
    return outcome;
  }

  /// Creates an account. With email confirmation on, the result is
  /// [AuthOutcome.confirmEmail] and nobody is signed in yet.
  Future<AuthOutcome> signUpWithEmail({required String name, required String email, required String password}) async {
    final service = auth;
    if (service == null) return AuthOutcome.failed;
    final outcome = await service.signUp(email: email, password: password, displayName: name);
    if (outcome == AuthOutcome.ok) _syncAccount(notify: false);
    notifyListeners();
    return outcome;
  }

  /// Deletes the signed-in person's own account (server-side), then clears
  /// everything on this device like sign out.
  /// Only for [expectedAccountId], the account the guest confirmed for: if
  /// another account is signed in by now, nothing is deleted or cleared.
  Future<AuthOutcome> deleteAccount({required String expectedAccountId}) async {
    final service = auth;
    if (service == null || _accountId != expectedAccountId) return AuthOutcome.failed;
    final outcome = await service.deleteAccount(expectedUserId: expectedAccountId);
    // The service already signed out the deleted account (and only it). Re-read
    // who is signed in now; that clears the deleted account's local data and
    // never signs out an account that replaced it.
    _syncAccount();
    return outcome;
  }

  void continueAsGuest() {
    _isGuest = true;
    notifyListeners();
  }

  void signOut() {
    final service = auth;
    if (service != null && service.isSignedIn) unawaited(service.signOut());
    if (_accountId != null) _accountGeneration++;
    _accountId = null;
    _nameRequest++;
    _clearUserData();
    notifyListeners();
  }

  /// Forgets everything about the person on this device (sign out, account
  /// deleted, or the session expired).
  void _clearUserData() {
    _displayName = null;
    _profile = null;
    search.radiusMeters = null;
    _isGuest = false;
    _searchLocation = null;
    _locationProblem = null;
    _locating = false;
    _lookingUpPlace = false;
    _locationRequest++;
    search.reset(); // the next user must not see this search
    // Bookmarks are real places now and aren't tied to an account yet, so
    // they go too: the next person on this phone must not see them.
    _bookmarks.clear();
    _bookmarkRatings.clear();
    notifyListeners();
  }

  bool isBookmarked(String placeId) => _bookmarks.any((r) => r.placeId == placeId);

  void toggleBookmark(Restaurant restaurant) {
    final existingIndex = _bookmarks.indexWhere((r) => r.placeId == restaurant.placeId);
    if (existingIndex >= 0) {
      _bookmarks.removeAt(existingIndex);
      _bookmarkRatings.remove(restaurant.placeId);
    } else {
      _bookmarks.add(restaurant);
    }
    notifyListeners();
  }

  void rateBookmark(String placeId, int rating) {
    if (!isBookmarked(placeId)) return;
    _bookmarkRatings[placeId] = rating.clamp(0, 5).toInt();
    notifyListeners();
  }

  void addDemoBookmarks() {
    for (final r in _suggested) {
      if (!isBookmarked(r.placeId)) _bookmarks.add(r);
    }
    notifyListeners();
  }
}

class AppSessionScope extends InheritedNotifier<AppSession> {
  const AppSessionScope({
    super.key,
    required AppSession session,
    required super.child,
  }) : super(notifier: session);

  static AppSession of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppSessionScope>();
    assert(scope != null, 'AppSessionScope not found in widget tree');
    return scope!.notifier!;
  }
}
