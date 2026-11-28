import 'restaurant.dart' show PhotoAuthor;

/// What the smart card shows about one place (TASK-UI-4), as the
/// `place-details` function sends it. Every value is a Google Places fact the
/// server already checked; anything missing or malformed is simply left out.
class PlaceDetails {
  final String placeId;
  final List<DetailPhoto> photos;
  final List<PlaceReview> reviews;
  final String? editorialSummary;

  /// Google's own summary of reviews, with the disclosure Google requires.
  final String? reviewSummary;
  final String? reviewSummaryDisclosure;
  final String? websiteUri;
  final String? mapsUri;

  /// Places attributes the server reported (for example `takeout: true`),
  /// in the server's order. An attribute Places didn't report is absent.
  final Map<String, bool> attributes;

  const PlaceDetails({
    required this.placeId,
    this.photos = const [],
    this.reviews = const [],
    this.editorialSummary,
    this.reviewSummary,
    this.reviewSummaryDisclosure,
    this.websiteUri,
    this.mapsUri,
    this.attributes = const {},
  });

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  static List<T> _list<T>(Object? v, T? Function(Map<String, dynamic>) read) => [
    if (v is List)
      for (final item in v)
        if (item is Map<String, dynamic>) ?read(item),
  ];

  static PhotoAuthor? _author(Map<String, dynamic> a) {
    final name = _text(a['name']);
    return name == null ? null : PhotoAuthor(name: name, uri: _text(a['uri']), avatarUri: _text(a['avatarUri']));
  }

  /// Null when [json] isn't a details answer for [placeId].
  static PlaceDetails? fromJson(Object? json, String placeId) {
    if (json is! Map<String, dynamic> || json['placeId'] != placeId) return null;
    final summary = json['reviewSummary'];
    final attributes = json['attributes'];
    return PlaceDetails(
      placeId: placeId,
      photos: _list(json['photos'], (p) {
        final name = _text(p['name']);
        final authors = _list(p['authors'], _author);
        return name == null || authors.isEmpty ? null : DetailPhoto(name: name, authors: authors, mapsUri: _text(p['mapsUri']));
      }),
      reviews: _list(json['reviews'], (r) {
        final author = _text(r['authorName']);
        final text = _text(r['text']);
        if (author == null || text == null) return null;
        final rating = r['rating'];
        return PlaceReview(
          authorName: author,
          authorUri: _text(r['authorUri']),
          authorPhotoUri: _text(r['authorPhotoUri']),
          rating: rating is num ? rating.toDouble() : null,
          relativeTime: _text(r['relativeTime']),
          text: text,
          mapsUri: _text(r['mapsUri']),
        );
      }),
      editorialSummary: _text(json['editorialSummary']),
      reviewSummary: summary is Map<String, dynamic> ? _text(summary['text']) : null,
      reviewSummaryDisclosure: summary is Map<String, dynamic> ? _text(summary['disclosure']) : null,
      websiteUri: _text(json['websiteUri']),
      mapsUri: _text(json['mapsUri']),
      attributes: {
        if (attributes is Map<String, dynamic>)
          for (final e in attributes.entries)
            if (e.value is bool) e.key: e.value as bool,
      },
    );
  }
}

class DetailPhoto {
  /// Places photo name; the image itself comes from `place-photo`.
  final String name;
  final List<PhotoAuthor> authors;
  final String? mapsUri;
  const DetailPhoto({required this.name, required this.authors, this.mapsUri});
}

class PlaceReview {
  final String authorName;
  final String? authorUri;
  final String? authorPhotoUri;
  final double? rating;
  final String? relativeTime;
  final String text;
  final String? mapsUri;
  const PlaceReview({
    required this.authorName,
    this.authorUri,
    this.authorPhotoUri,
    this.rating,
    this.relativeTime,
    required this.text,
    this.mapsUri,
  });
}
