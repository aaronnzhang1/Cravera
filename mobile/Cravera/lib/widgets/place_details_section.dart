import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_colors.dart';
import '../models/place_details.dart';
import '../models/restaurant.dart';
import '../services/craving_search.dart';

/// How each Places attribute reads, when Places reports it.
const attributeLabels = {
  'takeout': ('Takeout', 'No takeout'),
  'delivery': ('Delivery', 'No delivery'),
  'dineIn': ('Dine-in', 'No dine-in'),
  'servesVegetarianFood': ('Vegetarian options', 'No vegetarian options'),
  'outdoorSeating': ('Outdoor seating', 'No outdoor seating'),
  'goodForGroups': ('Good for groups', 'Not for groups'),
  'servesBeer': ('Beer', 'No beer'),
  'servesWine': ('Wine', 'No wine'),
};

/// The smart card's body under the pick's facts (TASK-UI-4). It loads by
/// itself when the place is shown: Cravera's take, Google's description and
/// review summary, and what the place offers, then "See full page".
class PlaceDetailsSection extends StatelessWidget {
  final CravingSearch search;
  final Restaurant restaurant;
  const PlaceDetailsSection({super.key, required this.search, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final load = search.currentDetails;
    return switch (load?.status) {
      null || DetailsStatus.loading => const _Thinking(),
      DetailsStatus.failed => _Failed(onRetry: search.openDetails),
      DetailsStatus.loaded => _Loaded(details: load!.details!, search: search, restaurant: restaurant),
    };
  }
}

/// Cravera at work while details load: the assistant, not a spinner.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cravera is reading up on this place…',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  final VoidCallback onRetry;
  const _Failed({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Couldn't load more about this place.",
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// Cravera's take: the assistant's note, labelled as AI and as built on
/// Google data and reviews (ADR 0005).
class TakePanel extends StatelessWidget {
  final String take;
  final bool isAi;
  const TakePanel({super.key, required this.take, required this.isAi});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
                const SizedBox(width: 6),
                Text("Cravera's take", style: text.titleSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(take, style: text.bodyLarge?.copyWith(color: AppColors.textPrimary, height: 1.35)),
            const SizedBox(height: 6),
            Text(
              isAi ? 'AI take, based on Google data and reviews' : 'Based on Google data',
              style: text.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  final PlaceDetails details;
  final CravingSearch search;
  final Restaurant restaurant;
  const _Loaded({required this.details, required this.search, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final offers = [
      for (final e in attributeLabels.entries)
        if (details.attributes[e.key] == true) e.value.$1,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (details.take != null) TakePanel(take: details.take!, isAi: details.takeIsAi),
          if (details.editorialSummary != null) ...[
            const SizedBox(height: 20),
            Text('About', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(details.editorialSummary!, style: text.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (details.reviewSummary != null) ...[
            const SizedBox(height: 20),
            _ReviewSummary(details: details, maxLines: 3),
          ],
          if (offers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Offers', style: text.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final o in offers) _Tag(label: o)],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showPlacePage(context, search: search, restaurant: restaurant, details: details),
              icon: const Icon(Icons.open_in_full_rounded, size: 18),
              label: const Text('See full page'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  final PlaceDetails details;

  /// Clamped on the card; the full page shows all of it.
  final int? maxLines;
  const _ReviewSummary({required this.details, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What people say', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          details.reviewSummary!,
          style: maxLines == null ? text.bodyLarge : text.bodyMedium,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
        ),
        // Google requires its disclosure with its AI review summary.
        if (details.reviewSummaryDisclosure != null) ...[
          const SizedBox(height: 4),
          Text(details.reviewSummaryDisclosure!, style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool yes;
  const _Tag({required this.label, this.yes = true});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(yes ? Icons.check_rounded : Icons.close_rounded, size: 16, color: yes ? AppColors.sage : AppColors.textMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: yes ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full page for a place, like a Yelp page, over the card. Swipe down or
/// tap Close to return to the same card.
Future<void> showPlacePage(
  BuildContext context, {
  required CravingSearch search,
  required Restaurant restaurant,
  required PlaceDetails details,
}) {
  search.loadAvatars([
    for (final r in details.reviews) PhotoAuthor(name: r.authorName, uri: r.authorUri, avatarUri: r.authorPhotoUri),
  ]);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListenableBuilder(
        listenable: search,
        builder: (context, _) => _PlacePage(
          scroll: scroll,
          search: search,
          restaurant: restaurant,
          details: details,
        ),
      ),
    ),
  );
}

class _PlacePage extends StatelessWidget {
  final ScrollController scroll;
  final CravingSearch search;
  final Restaurant restaurant;
  final PlaceDetails details;
  const _PlacePage({required this.scroll, required this.search, required this.restaurant, required this.details});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final gallery = search.currentGallery;
    final reported = [
      for (final e in attributeLabels.entries)
        if (details.attributes[e.key] != null) (e.value, details.attributes[e.key]!),
    ];
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(restaurant.name, style: text.headlineSmall)),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        if (gallery.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 204,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // Only photos scrolled into view load: nothing ahead of time.
              cacheExtent: 0,
              itemCount: gallery.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _Thumb(photo: gallery[i], search: search),
            ),
          ),
        ],
        if (details.take != null) ...[
          const SizedBox(height: 16),
          TakePanel(take: details.take!, isAi: details.takeIsAi),
        ],
        if (details.editorialSummary != null) ...[
          const SizedBox(height: 16),
          Text('About', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(details.editorialSummary!, style: text.bodyLarge),
        ],
        if (details.reviewSummary != null) ...[
          const SizedBox(height: 16),
          _ReviewSummary(details: details),
        ],
        if (reported.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Amenities', style: text.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final ((yes, no), value) in reported) _Tag(label: value ? yes : no, yes: value)],
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (details.websiteUri != null)
              _LinkButton(icon: Icons.restaurant_menu_rounded, label: 'Website & menu', uri: details.websiteUri!),
            if (details.mapsUri != null)
              _LinkButton(icon: Icons.map_outlined, label: 'Google Maps', uri: details.mapsUri!),
          ],
        ),
        if (details.reviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Reviews', style: text.titleMedium),
          for (final r in details.reviews) _ReviewTile(review: r, search: search),
        ],
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final DetailPhoto photo;
  final CravingSearch search;
  const _Thumb({required this.photo, required this.search});

  @override
  Widget build(BuildContext context) {
    search.loadGalleryPhoto(photo);
    final bytes = search.galleryPhoto(photo.name);
    final author = photo.authors.isEmpty ? null : photo.authors.first;
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 150,
              width: 220,
              color: AppColors.surface2,
              child: bytes == null
                  ? const Icon(Icons.restaurant_rounded, color: AppColors.textMuted)
                  : Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          ),
          // Google requires the author with the photo.
          if (bytes != null && author != null)
            _LinkText(label: 'Photo: ${photo.authors.map((a) => a.name).join(', ')}', uri: author.uri),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final PlaceReview review;
  final CravingSearch search;
  const _ReviewTile({required this.review, required this.search});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final avatar = search.avatar(review.authorPhotoUri);
    final rating = review.rating;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: Container(
                  width: 32,
                  height: 32,
                  color: AppColors.surface2,
                  alignment: Alignment.center,
                  child: avatar == null
                      ? Text(review.authorName.characters.first.toUpperCase(), style: text.labelLarge)
                      : Image.memory(avatar, width: 32, height: 32, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _LinkText(label: review.authorName, uri: review.authorUri, style: text.titleSmall)),
            ],
          ),
          Row(
            children: [
              if (rating != null)
                Semantics(
                  label: 'Rated ${rating.toStringAsFixed(0)} out of 5',
                  child: ExcludeSemantics(
                    child: Text('★' * rating.round() + '☆' * (5 - rating.round()), style: text.bodyMedium?.copyWith(color: AppColors.gold)),
                  ),
                ),
              if (review.relativeTime != null) ...[
                const SizedBox(width: 8),
                Text(review.relativeTime!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(review.text, style: text.bodyMedium),
          if (review.mapsUri != null) _LinkText(label: 'View on Google Maps', uri: review.mapsUri),
        ],
      ),
    );
  }
}

/// A text link that opens outside the app, at least 48 dp tall; plain text without a link.
class _LinkText extends StatelessWidget {
  final String label;
  final String? uri;
  final TextStyle? style;
  const _LinkText({required this.label, required this.uri, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.labelMedium;
    final link = uri == null ? null : Uri.tryParse(uri!);
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: Text(label, style: base?.copyWith(decoration: link == null ? null : TextDecoration.underline)),
      ),
    );
    if (link == null) return body;
    return InkWell(onTap: () => launchUrl(link, mode: LaunchMode.externalApplication), child: body);
  }
}

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String uri;
  const _LinkButton({required this.icon, required this.label, required this.uri});

  @override
  Widget build(BuildContext context) {
    final link = Uri.tryParse(uri);
    return OutlinedButton.icon(
      onPressed: link == null ? null : () => launchUrl(link, mode: LaunchMode.externalApplication),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}
