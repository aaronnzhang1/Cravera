import 'package:flutter/widgets.dart';

import '../models/restaurant.dart';
import '../services/location_service.dart';

class AppSession extends ChangeNotifier {
  AppSession({this.locationService = const LocationService()});

  /// Finds where to search. Tests pass a fake.
  final LocationService locationService;

  String? _displayName;
  SearchLocation? _searchLocation;
  LocationProblem? _locationProblem;
  bool _locating = false;

  /// Bumped on sign out. A location lookup that started before then finishes
  /// into a session that no longer exists, so its result is dropped instead
  /// of handing the old user's location to the next one.
  int _locationGeneration = 0;
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
    _locating = true;
    notifyListeners();
    final generation = _locationGeneration;
    final result = await locationService.current();
    if (generation != _locationGeneration) return; // signed out meanwhile
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
    final generation = _locationGeneration;
    final found = await locationService.lookUp(place);
    if (generation != _locationGeneration) return false; // signed out meanwhile
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
    _locationGeneration++;
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
