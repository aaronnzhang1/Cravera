import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/place_details.dart';
import '../services/craving_search.dart';

/// The smart card's "more about this place" part (TASK-UI-4), under the
/// pick's facts. Nothing loads until the guest asks: then one details request
/// goes out, and the pick becomes a longer page that scrolls. The No / Yes
/// footer stays where it is the whole time.
class PlaceDetailsSection extends StatelessWidget {
  final CravingSearch search;
  const PlaceDetailsSection({super.key, required this.search});

  @override
  Widget build(BuildContext context) {
    final load = search.currentDetails;
    return switch (load?.status) {
      null => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          onPressed: search.openDetails,
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('More about this place'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      DetailsStatus.loading => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Semantics(
            label: 'Loading more about this place',
            child: const CircularProgressIndicator(),
          ),
        ),
      ),
      DetailsStatus.failed => _Failed(onRetry: search.openDetails),
      DetailsStatus.loaded => _Loaded(details: load!.details!),
    };
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

class _Loaded extends StatelessWidget {
  final PlaceDetails details;
  const _Loaded({required this.details});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final about = details.editorialSummary;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            about ?? "Google doesn't have a description of this place.",
            style: text.bodyLarge?.copyWith(color: about == null ? AppColors.textMuted : AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
