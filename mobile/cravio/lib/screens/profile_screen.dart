import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../core/session.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileHeader(name: session.displayName),
          const SizedBox(height: 14),
          _MenuCard(
            items: [
              _MenuItem(
                icon: Icons.bookmark_rounded,
                title: 'Bookmarks',
                subtitle: '${session.bookmarks.length} saved',
                onTap: () => context.go(AppRoutes.appBookmarks),
              ),
              _MenuItem(
                icon: Icons.auto_awesome_rounded,
                title: 'Results',
                subtitle: 'Result overlay + details',
                onTap: () => context.go(AppRoutes.appResults),
              ),
              _MenuItem(
                icon: Icons.group_outlined,
                title: 'Friends',
                subtitle: 'Share and discover',
                onTap: () => context.go(AppRoutes.appFriends),
              ),
              _MenuItem(
                icon: Icons.inbox_outlined,
                title: 'Recs inbox',
                subtitle: 'Incoming recommendations',
                onTap: () => context.go(AppRoutes.appRecs),
              ),
              _MenuItem(
                icon: Icons.map_outlined,
                title: 'Navigate',
                subtitle: 'Directions + quick actions',
                onTap: () => context.go(AppRoutes.appNavigate),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                session.signOut();
                context.go(AppRoutes.signIn);
              },
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  const _ProfileHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border.withValues(alpha: 0.55), width: 1),
              ),
              child: const Icon(Icons.person_rounded, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface2.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.35), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text('Cravio member', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _MenuCard extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _MenuRow(item: items[i]),
              if (i != items.length - 1)
                Divider(height: 0, color: AppColors.border.withValues(alpha: 0.25)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final _MenuItem item;
  const _MenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface2.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.35), width: 1),
              ),
              child: Icon(item.icon, color: AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(item.subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

