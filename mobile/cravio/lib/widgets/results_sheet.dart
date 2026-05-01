import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = min(screenHeight - bottomInset - 32, max(360.0, screenHeight * 0.74));

    final primaryMeta = [
      if (restaurant.rating != null) '${restaurant.rating!.toStringAsFixed(1)}/5',
      if ((restaurant.cuisine ?? '').trim().isNotEmpty) restaurant.cuisine!.trim(),
      if (restaurant.priceLevel != null) '\$' * restaurant.priceLevel!.clamp(1, 4),
    ].join('  •  ');
    final distanceLabel = restaurant.distanceMeters == null ? null : '${(restaurant.distanceMeters! / 1000).toStringAsFixed(1)} km away';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: sheetHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                border: Border.all(color: AppColors.border.withValues(alpha: 0.55), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      children: [
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _PhotoHeader(photoUrl: restaurant.photoUrl),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                restaurant.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
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
                        if (primaryMeta.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            primaryMeta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                        if ((restaurant.address ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            [
                              restaurant.address!.trim(),
                              if (distanceLabel != null) distanceLabel,
                            ].join('  •  '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                          ),
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
                                onPressed: () => _showNextActions(context, restaurant),
                                child: const Text('Yes'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showNextActions(BuildContext context, Restaurant restaurant) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.navigation_rounded),
              title: const Text('Navigate there'),
              subtitle: const Text('Open directions in your maps app'),
              onTap: () async {
                Navigator.of(context).pop();
                await _openNavigation(context, restaurant);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Close for now'),
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _openNavigation(BuildContext context, Restaurant restaurant) async {
  final encoded = Uri.encodeComponent(restaurant.name);
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!context.mounted) return;
  if (!launched) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open navigation app.')),
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  final String? photoUrl;
  const _PhotoHeader({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 150,
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
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: AppColors.textPrimary),
      ),
    );
  }
}
