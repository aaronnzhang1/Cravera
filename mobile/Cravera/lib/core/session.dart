import 'package:flutter/widgets.dart';

import '../models/restaurant.dart';
import '../services/craving_search.dart';
import '../services/location_service.dart';

class AppSession extends ChangeNotifier {
  AppSession({this.locationService = const LocationService(), CravingSearch? search})
      : search = search ?? CravingSearch() {
    // Screens listen to the session, so pass search changes on.
    this.search.addListener(notifyListeners);
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

  bool get isSignedIn => _displayName != null && _displayName!.trim().isNotEmpty;

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

  /// Uses the device location. On failure, keeps any typed place already set.
  Future<void> useDeviceLocation() async {
    if (_locating) return;
    final request = ++_locationRequest;
    _locating = true;
    notifyListeners();
    final result = await locationService.current();
    if (request != _locationRequest) return; // a newer choice or sign out won
    _locating = false;
    if (result.location != null) {
      _searchLocation = result.location;
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
    final found = await locationService.lookUp(place);
    if (request != _locationRequest) return false; // a newer choice or sign out won
    if (found == null) return false;
    _searchLocation = found;
    notifyListeners();
    return true;
  }

  void signIn({required String displayName}) {
    _displayName = displayName.trim().isEmpty ? 'there' : displayName.trim();
    _isGuest = false;
    notifyListeners();
  }

  void continueAsGuest() {
    _isGuest = true;
    notifyListeners();
  }

  void signOut() {
    _displayName = null;
    _isGuest = false;
    _searchLocation = null;
    _locationProblem = null;
    _locating = false;
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
