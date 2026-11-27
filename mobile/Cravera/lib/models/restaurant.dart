class Restaurant {
  final String placeId;
  final String name;
  final String? photoUrl;

  /// Google Places photo resource name (`places/<id>/photos/<id>`). Turning it
  /// into an image needs the server, because the Places key must stay there.
  final String? photoName;
  final String? cuisine;
  final String? address;
  final int? priceLevel;
  final int? distanceMeters;
  final double? rating;

  /// Where the place is, for directions to this exact place.
  final double? latitude;
  final double? longitude;

  const Restaurant({
    required this.placeId,
    required this.name,
    this.photoUrl,
    this.photoName,
    this.cuisine,
    this.address,
    this.priceLevel,
    this.distanceMeters,
    this.rating,
    this.latitude,
    this.longitude,
  });
}
