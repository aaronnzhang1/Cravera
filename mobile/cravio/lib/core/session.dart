import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/restaurant.dart';

class AppSession extends ChangeNotifier {
  String? _displayName;
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

  bool get isSignedIn => _displayName != null && _displayName!.trim().isNotEmpty;
  String get displayName => (_displayName ?? '').trim().isEmpty ? 'there' : _displayName!.trim();

  List<Restaurant> get bookmarks => List.unmodifiable(_bookmarks);
  List<Restaurant> get suggestedRestaurants => List.unmodifiable(_suggested);
  int bookmarkRating(String placeId) => _bookmarkRatings[placeId] ?? 0;

  void signIn({required String displayName}) {
    _displayName = displayName.trim().isEmpty ? 'there' : displayName.trim();
    notifyListeners();
  }

  void signOut() {
    _displayName = null;
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
