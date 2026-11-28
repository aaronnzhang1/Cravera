import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/restaurant.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/craving_search.dart';
import '../services/location_service.dart';
import '../services/saved_hub.dart';
import '../services/saved_places_service.dart';

class AppSession extends ChangeNotifier {
  AppSession({this.locationService = const LocationService(), CravingSearch? search, this.auth, this.profiles, SavedHub? saved})
      : search = search ?? CravingSearch(),
        saved = saved ?? SavedHub() {
    // Screens listen to the session, so pass search and Saved changes on.
    this.search.addListener(notifyListeners);
    this.saved.addListener(notifyListeners);
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
    // Saved follows the account: the previous person's places are cleared.
    saved.switchAccount(id);
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

  /// True when the profile couldn't be loaded; [retryProfileLoad] tries again.
  bool _profileLoadFailed = false;
  bool get profileLoadFailed => _profileLoadFailed;

  /// Completes when the signed-in person's profile has loaded (or failed), so
  /// a search right after sign-in uses their saved distance.
  /// Waits at most [profileWait]: a stalled load never blocks search (it
  /// then uses the server's default distance).
  Future<void> get profileReady =>
      (_profileLoad ?? Future.value()).timeout(profileWait, onTimeout: () {});
  static const profileWait = Duration(seconds: 5);
  Future<void>? _profileLoad;

  /// Loads the signed-in person's profile (or just the display name without a
  /// profile service); dropped if the account changed or signed out meanwhile.
  Future<void> _loadDisplayName(String accountId, int request) {
    return _profileLoad = () async {
      // Bounded: a read that never answers shows "Try again", not "Loading…".
      final loaded = await profiles?.load(accountId).timeout(profileWait, onTimeout: () => null);
      final name = loaded?.displayName ?? await auth?.displayName().timeout(profileWait, onTimeout: () => null);
      if (request != _nameRequest || _accountId != accountId) return;
      _profile = loaded;
      _profileLoadFailed = profiles != null && loaded == null;
      search.radiusMeters = loaded?.defaultRadiusMeters;
      _displayName = name ?? auth?.email?.split('@').first ?? 'there';
      notifyListeners();
    }();
  }

  /// Tries loading the profile again after a failure.
  Future<void> retryProfileLoad() async {
    final account = _accountId;
    if (account == null || !_profileLoadFailed) return;
    _profileLoadFailed = false;
    notifyListeners();
    await _loadDisplayName(account, ++_nameRequest);
  }

  /// Saves one edit to the signed-in person's profile. Only the edited field
  /// is sent, and the stored row the server returns replaces the copy here.
  /// Bound to the account signed in when it was called: if that changes
  /// before the answer, the answer is dropped (and RLS stops a write to
  /// another person's row).
  Future<ProfileSaveOutcome> updateProfile(ProfileChange change) async {
    final service = profiles;
    final account = _accountId;
    if (service == null || account == null || _profile == null) return ProfileSaveOutcome.failed;
    if (change.toColumns() == null) return ProfileSaveOutcome.invalid;
    final generation = _accountGeneration;
    // One save at a time, in the order they were made: a quick second edit
    // can't be overwritten by the first one arriving late, and an older
    // answer can't replace a newer one on screen.
    final before = _saving;
    final done = Completer<void>();
    _saving = done.future;
    _savesInFlight++;
    notifyListeners();
    try {
      await before;
      if (_accountId != account || _accountGeneration != generation) return ProfileSaveOutcome.failed;
      return await _save(service, account, generation, change);
    } finally {
      done.complete();
      // An account change reset the counter; an old save can't touch it.
      if (_accountGeneration == generation) {
        _savesInFlight--;
        notifyListeners();
      }
    }
  }

  /// The save in flight, if any; the next one waits for it.
  Future<void> _saving = Future.value();

  /// True while a profile save is on its way. Editors are closed meanwhile,
  /// so an edit can't start from a value that is about to change.
  bool get profileSaving => _savesInFlight > 0;
  int _savesInFlight = 0;

  Future<ProfileSaveOutcome> _save(ProfileService service, String account, int generation, ProfileChange change) async {
    // Bounded: a save that never answers counts as a lost answer (then the
    // stored row is read back), so the editors can't stay locked.
    final (outcome, stored) = await service
        .save(account, change)
        .timeout(profileWait * 2, onTimeout: () => (ProfileSaveOutcome.network, null));
    if (_accountId != account || _accountGeneration != generation) return ProfileSaveOutcome.failed;
    if (outcome == ProfileSaveOutcome.network) {
      // The answer was lost, but the row may have been saved: show what is
      // stored now (settings and search distance), if it can be read.
      // Bounded: a read that never answers mustn't keep the editors locked.
      final now = await service.load(account).timeout(profileWait * 2, onTimeout: () => null);
      if (now != null && _accountId == account && _accountGeneration == generation) {
        _profile = now;
        _displayName = now.displayName;
        search.radiusMeters = now.defaultRadiusMeters;
        notifyListeners();
      }
      return ProfileSaveOutcome.network;
    }
    if (outcome != ProfileSaveOutcome.ok || stored == null) return outcome == ProfileSaveOutcome.ok ? ProfileSaveOutcome.failed : outcome;
    _profile = stored;
    _displayName = stored.displayName;
    search.radiusMeters = stored.defaultRadiusMeters;
    notifyListeners();
    return ProfileSaveOutcome.ok;
  }

  /// Finds where to search. Tests pass a fake.
  final LocationService locationService;

  /// The current craving search and its results. Tests pass one with a fake
  /// [PlacesService].
  final CravingSearch search;

  /// The signed-in person's saved places (TASK-004). Tests pass a fake service.
  final SavedHub saved;

  String? _displayName;
  SearchLocation? _searchLocation;
  LocationProblem? _locationProblem;
  bool _locating = false;

  /// Numbers each location request. Only the newest may write its result:
  /// an older GPS or typed lookup that finishes late is dropped, so it can't
  /// replace the user's newer choice, or hand a signed-out user's location
  /// to the next one. Sign out also bumps it.
  int _locationRequest = 0;
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
    _profileLoadFailed = false;
    // A save from the previous person neither delays nor locks the next one's.
    _saving = Future.value();
    _savesInFlight = 0;
    _profileLoad = null;
    search.radiusMeters = null;
    _isGuest = false;
    _searchLocation = null;
    _locationProblem = null;
    _locating = false;
    _lookingUpPlace = false;
    _locationRequest++;
    search.reset(); // the next user must not see this search
    saved.switchAccount(null); // the next person on this phone must not see these
    notifyListeners();
  }

  /// Whether the signed-in person has saved [placeId].
  bool isBookmarked(String placeId) => isSignedIn && saved.contains(placeId);

  /// Saves or unsaves [restaurant] for the signed-in person. Null for guests:
  /// nothing is saved on the device as if it were (the screen asks them to
  /// create an account).
  Future<SavedOutcome?> toggleBookmark(Restaurant restaurant) async {
    if (!isSignedIn) return null;
    return saved.contains(restaurant.placeId) ? saved.remove(restaurant.placeId) : saved.add(restaurant.placeId);
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
