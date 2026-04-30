import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/session.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final bookmarks = session.bookmarks;

    return SafeArea(
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
                      'No saved restaurants yet.\nWhen you save one, it’ll show up here.',
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
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bookmarks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final r = bookmarks[index];
                return _BookmarkCard(
                  restaurantName: r.name,
                  cuisine: r.cuisine,
                  address: r.address,
                  rating: r.rating,
                  priceLevel: r.priceLevel,
                  distanceMeters: r.distanceMeters,
                  photoUrl: r.photoUrl,
                  onRemove: () => session.toggleBookmark(r),
                );
              },
            ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final String restaurantName;
  final String? cuisine;
  final String? address;
  final double? rating;
  final int? priceLevel;
  final int? distanceMeters;
  final String? photoUrl;
  final VoidCallback onRemove;

  const _BookmarkCard({
    required this.restaurantName,
    required this.cuisine,
    required this.address,
    required this.rating,
    required this.priceLevel,
    required this.distanceMeters,
    required this.photoUrl,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final metaChips = <Widget>[];

    if (rating != null) metaChips.add(_MetaChip(icon: Icons.star_rounded, label: rating!.toStringAsFixed(1)));
    if ((cuisine ?? '').trim().isNotEmpty) metaChips.add(_MetaChip(icon: Icons.local_dining_rounded, label: cuisine!.trim()));
    if (priceLevel != null) metaChips.add(_MetaChip(icon: Icons.attach_money_rounded, label: '\$' * priceLevel!.clamp(1, 4)));
    if (distanceMeters != null) {
      metaChips.add(_MetaChip(icon: Icons.place_rounded, label: '${(distanceMeters! / 1000).toStringAsFixed(1)} km'));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.40), width: 1),
                ),
                child: photoUrl == null
                    ? const Icon(Icons.restaurant_rounded, color: AppColors.textSecondary, size: 28)
                    : Image.network(photoUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(restaurantName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (metaChips.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: metaChips,
                    ),
                  if ((address ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              icon: Icons.bookmark_remove_rounded,
              onPressed: onRemove,
            ),
          ],
        ),
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
        icon: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

