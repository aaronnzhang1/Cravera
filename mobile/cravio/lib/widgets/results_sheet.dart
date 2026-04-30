import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/session.dart';
import '../models/restaurant.dart';

Future<void> showResultsSheet(BuildContext context, {String? prompt}) async {
  final session = AppSessionScope.of(context);
  final items = session.suggestedRestaurants;
  if (items.isEmpty) return;

  // Demo: pick a stable "random" result each open.
  final selected = items[DateTime.now().millisecondsSinceEpoch % max(1, items.length)];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      return _ResultsSheetBody(restaurant: selected, prompt: prompt);
    },
  );
}

class _ResultsSheetBody extends StatelessWidget {
  final Restaurant restaurant;
  final String? prompt;
  const _ResultsSheetBody({required this.restaurant, required this.prompt});

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final saved = session.isBookmarked(restaurant.placeId);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final chips = <Widget>[
      if (restaurant.rating != null) _Chip(icon: Icons.star_rounded, text: restaurant.rating!.toStringAsFixed(1)),
      if ((restaurant.cuisine ?? '').trim().isNotEmpty) _Chip(icon: Icons.local_dining_rounded, text: restaurant.cuisine!.trim()),
      if (restaurant.priceLevel != null) _Chip(icon: Icons.attach_money_rounded, text: '\$' * restaurant.priceLevel!.clamp(1, 4)),
      if (restaurant.distanceMeters != null) _Chip(icon: Icons.place_rounded, text: '${(restaurant.distanceMeters! / 1000).toStringAsFixed(1)} km'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface2.withValues(alpha: 0.80),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.55), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.62,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Result',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if ((prompt ?? '').trim().isNotEmpty) ...[
                      Text(
                        'For: ${prompt!.trim()}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _PhotoHeader(photoUrl: restaurant.photoUrl),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            restaurant.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RoundIcon(
                          icon: saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                          onPressed: () => session.toggleBookmark(restaurant),
                        ),
                      ],
                    ),
                    if ((restaurant.address ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        restaurant.address!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: chips),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('No'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Yes'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  final String? photoUrl;
  const _PhotoHeader({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.40), width: 1),
        ),
        child: photoUrl == null
            ? const Center(
                child: Icon(Icons.restaurant_rounded, color: AppColors.textSecondary, size: 44),
              )
            : Image.network(photoUrl!, fit: BoxFit.cover),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _RoundIcon({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.45), width: 1),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.textPrimary),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.40), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

