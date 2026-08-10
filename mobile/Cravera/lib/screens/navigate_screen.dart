import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class NavigateScreen extends StatelessWidget {
  const NavigateScreen({super.key});

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
                  Text('Directions (demo)', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Placeholder UI until we connect Maps + deep links.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.directions_rounded, color: AppColors.textSecondary),
                  title: const Text('Open directions'),
                  subtitle: const Text('Google Maps / Apple Maps'),
                  trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.textMuted),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Maps deep link coming soon')),
                  ),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.call_rounded, color: AppColors.textSecondary),
                  title: const Text('Call restaurant'),
                  subtitle: const Text('Tap-to-call'),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Phone integration coming soon')),
                  ),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: AppColors.textSecondary),
                  title: const Text('Share'),
                  subtitle: const Text('Send to a friend'),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share flow coming soon')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

