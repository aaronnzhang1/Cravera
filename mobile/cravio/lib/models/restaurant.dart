class Restaurant {
  final String placeId;
  final String name;
  final String? photoUrl;
  final String? cuisine;
  final String? address;
  final int? priceLevel;
  final int? distanceMeters;
  final double? rating;

  const Restaurant({
    required this.placeId,
    required this.name,
    this.photoUrl,
    this.cuisine,
    this.address,
    this.priceLevel,
    this.distanceMeters,
    this.rating,
  });
}
