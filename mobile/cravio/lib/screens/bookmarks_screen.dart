import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/session.dart';
import '../models/restaurant.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final bookmarks = session.bookmarks;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: bookmarks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmark_outline_rounded, size: 42, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      'No saved restaurants yet.\nWhen you save one, it will show up here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: session.addDemoBookmarks,
                      child: const Text('Add demo bookmarks'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bookmarks', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${bookmarks.length} restaurants', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 118),
                    itemCount: bookmarks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final r = bookmarks[index];
                      return _BookmarkCard(
                        restaurant: r,
                        userRating: session.bookmarkRating(r.placeId),
                        onRate: (rating) => session.rateBookmark(r.placeId, rating),
                        onRemove: () => session.toggleBookmark(r),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final Restaurant restaurant;
  final int userRating;
  final ValueChanged<int> onRate;
  final VoidCallback onRemove;

  const _BookmarkCard({
    required this.restaurant,
    required this.userRating,
    required this.onRate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => _showBookmarkDetails(context, restaurant),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.40), width: 1),
                  ),
                  child: restaurant.photoUrl == null || restaurant.photoUrl!.trim().isEmpty
                      ? const Icon(Icons.restaurant_rounded, color: AppColors.textSecondary, size: 24)
                      : Image.network(restaurant.photoUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _RatingControl(
                      value: userRating,
                      onChanged: onRate,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _RoundIconButton(
                icon: Icons.bookmark_remove_rounded,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showBookmarkDetails(BuildContext context, Restaurant restaurant) {
  final distanceLabel = restaurant.distanceMeters == null ? null : '${(restaurant.distanceMeters! / 1000).toStringAsFixed(1)} km away';
  final priceLabel = restaurant.priceLevel == null ? null : '\$' * restaurant.priceLevel!.clamp(1, 4);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface2.withValues(alpha: 0.94),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.55), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.border.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _RestaurantPhoto(photoUrl: restaurant.photoUrl),
                  const SizedBox(height: 14),
                  _DetailGrid(
                    items: [
                      _DetailItem(icon: Icons.star_rounded, label: 'Rating', value: restaurant.rating == null ? 'Not listed' : '${restaurant.rating!.toStringAsFixed(1)}/5'),
                      _DetailItem(icon: Icons.place_rounded, label: 'Distance', value: distanceLabel ?? 'Not listed'),
                      _DetailItem(icon: Icons.local_dining_rounded, label: 'Cuisine', value: restaurant.cuisine ?? 'Not listed'),
                      _DetailItem(icon: Icons.attach_money_rounded, label: 'Price', value: priceLabel ?? 'Not listed'),
                    ],
                  ),
                  if ((restaurant.address ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _AddressRow(address: restaurant.address!.trim()),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RatingControl extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingControl({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = value.clamp(0, 5).toInt();

    return PopupMenuButton<int>(
      onSelected: onChanged,
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      itemBuilder: (context) {
        return [
          for (var rating = 1; rating <= 5; rating++)
            PopupMenuItem<int>(
              value: rating,
              child: Text('$rating/5'),
            ),
        ];
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: normalizedValue == 0 ? AppColors.surface2.withValues(alpha: 0.35) : AppColors.accent.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.45), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              normalizedValue == 0 ? Icons.keyboard_arrow_down_rounded : Icons.star_rounded,
              size: 16,
              color: normalizedValue == 0 ? AppColors.textMuted : AppColors.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              normalizedValue == 0 ? 'Rate' : 'You $normalizedValue/5',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: normalizedValue == 0 ? AppColors.textMuted : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantPhoto extends StatelessWidget {
  final String? photoUrl;

  const _RestaurantPhoto({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.40), width: 1),
        ),
        child: photoUrl == null || photoUrl!.trim().isEmpty
            ? const Center(
                child: Icon(Icons.restaurant_rounded, color: AppColors.textSecondary, size: 44),
              )
            : Image.network(photoUrl!, fit: BoxFit.cover),
      ),
    );
  }
}

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _DetailGrid extends StatelessWidget {
  final List<_DetailItem> items;

  const _DetailGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 78,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.42), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(item.icon, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddressRow extends StatelessWidget {
  final String address;

  const _AddressRow({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.42), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              address,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _RoundIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.40), width: 1),
      ),
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }
}
