import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../widgets/glass.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  // Fictional demo friends until accounts exist (Phase 3).
  static const _demo = [('Maya', '🍜'), ('Jordan', '🌮'), ('Sam', '🍣')];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      // Bottom padding clears the floating nav bar.
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        const PageHeader(
          title: 'Friends',
          subtitle: 'Share picks with people you eat with.',
        ),
        Glass(
          tint: AppColors.sage,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.sage),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Demo only: real friends and recommendations arrive with accounts.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Glass(
          child: Column(
            children: [
              for (var i = 0; i < _demo.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 72, color: AppColors.glassEdge),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.accentSoft,
                    child: Text(_demo[i].$2, style: const TextStyle(fontSize: 20)),
                  ),
                  title: Text(_demo[i].$1, style: text.titleMedium),
                  subtitle: Text('Send a recommendation', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                  trailing: const Icon(Icons.send_rounded, size: 20, color: AppColors.textMuted),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sending recs to ${_demo[i].$1} is coming soon')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
