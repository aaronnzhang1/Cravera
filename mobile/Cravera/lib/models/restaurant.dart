class Restaurant {
  final String placeId;
  final String name;
  final String? photoUrl;

  /// Google Places photo resource name (`places/<id>/photos/<id>`). Turning it
  /// into an image needs the server, because the Places key must stay there.
  final String? photoName;

  /// Who took the photo, and their page. Google requires showing this with the photo.
  final String? photoAuthor;
  final String? photoAuthorUri;

  /// Every author of the photo (name, page, avatar). Google requires
  /// crediting them with the photo. Falls back to [photoAuthor] when empty.
  final List<PhotoAuthor> photoAuthors;

  /// The photo on Google Maps (https Google link). Google requires that the
  /// guest can open it.
  final String? photoMapsUri;
  final String? cuisine;
  final String? address;
  final int? priceLevel;
  final int? distanceMeters;
  final double? rating;

  /// Where the place is, for directions to this exact place.
  final double? latitude;
  final double? longitude;

  /// Why this pick (for example "In your price range"). The server builds
  /// these in code from this place's Places facts and the guest's request;
  /// they are never text from the AI model.
  final List<String> reasons;

  const Restaurant({
    required this.placeId,
    required this.name,
    this.photoUrl,
    this.photoName,
    this.photoAuthor,
    this.photoAuthorUri,
    this.photoAuthors = const [],
    this.photoMapsUri,
    this.cuisine,
    this.address,
    this.priceLevel,
    this.distanceMeters,
    this.rating,
    this.latitude,
    this.longitude,
    this.reasons = const [],
  });

  /// Who to credit for the photo: [photoAuthors], or the single
  /// [photoAuthor] that older servers send.
  List<PhotoAuthor> get photoCredits => photoAuthors.isNotEmpty || photoAuthor == null
      ? photoAuthors
      : [PhotoAuthor(name: photoAuthor!, uri: photoAuthorUri)];
}

/// One photo author, as Google Places credits them.
class PhotoAuthor {
  final String name;

  /// Their Google Maps profile (https), if given.
  final String? uri;

  /// Their avatar on Google's image host (https), if given.
  final String? avatarUri;

  const PhotoAuthor({required this.name, this.uri, this.avatarUri});
}
