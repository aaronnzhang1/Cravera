import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class RecsInboxScreen extends StatelessWidget {
  const RecsInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Incoming recommendations (demo)', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Placeholder content until we wire up real sharing.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final rec in const [
            ('Maya', 'Try Cedar & Citrus — you’ll love the pita.'),
            ('Jordan', 'Nori House has a great omakase.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.25),
                    child: const Icon(Icons.inbox_rounded, color: AppColors.textSecondary),
                  ),
                  title: Text(rec.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(rec.$2),
                  trailing: FilledButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Accepted rec from ${rec.$1} (coming soon)')),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

