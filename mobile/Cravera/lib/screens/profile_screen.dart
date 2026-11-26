import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../core/session.dart';
import '../widgets/glass.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final text = Theme.of(context).textTheme;
    final name = session.isGuest ? 'Guest' : session.displayName;
    final rated = session.bookmarks.where((r) => session.bookmarkRating(r.placeId) > 0).length;

    void comingSoon(String what) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$what is coming soon')),
        );

    return ListView(
      // Bottom padding clears the floating nav bar.
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        const PageHeader(title: 'Profile'),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.accentLight, AppColors.accentPressed],
                  ),
                ),
                alignment: Alignment.center,
                child: session.isGuest
                    ? const Icon(Icons.person_rounded, color: AppColors.onAccent, size: 30)
                    : Text(name[0].toUpperCase(), style: text.headlineSmall?.copyWith(color: AppColors.onAccent)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: text.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      session.isGuest ? 'Browsing as a guest' : 'Signed in',
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: '${session.bookmarks.length}',
                label: 'Saved',
                onTap: () => context.go(AppRoutes.appBookmarks),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _Stat(value: '$rated', label: 'Rated')),
          ],
        ),
        if (session.isGuest) ...[
          const SizedBox(height: 12),
          Glass(
            tint: AppColors.accent,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Keep your saves', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Create an account so your bookmarks and ratings follow you and shape your picks.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () {
                    session.signOut();
                    context.go(AppRoutes.signUp);
                  },
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ],
        const _SectionLabel('Preferences'),
        Glass(
          child: Column(
            children: [
              _Row(icon: Icons.restaurant_menu_rounded, title: 'Dietary preferences', onTap: () => comingSoon('Dietary preferences')),
              const _RowDivider(),
              _Row(icon: Icons.near_me_rounded, title: 'Location', onTap: () => comingSoon('Location settings')),
              const _RowDivider(),
              _Row(icon: Icons.notifications_none_rounded, title: 'Notifications', onTap: () => comingSoon('Notification settings')),
            ],
          ),
        ),
        const _SectionLabel('About'),
        Glass(
          child: Column(
            children: [
              _Row(icon: Icons.shield_outlined, title: 'Privacy & data', onTap: () => comingSoon('Privacy & data')),
              const _RowDivider(),
              _Row(icon: Icons.help_outline_rounded, title: 'Help & support', onTap: () => comingSoon('Help & support')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Glass(
          child: _Row(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            color: AppColors.danger,
            onTap: () {
              // Clear any message that might mention the old user's place.
              ScaffoldMessenger.of(context).clearSnackBars();
              session.signOut();
              context.go(AppRoutes.signIn);
            },
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _Stat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Glass(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(value, style: text.headlineSmall?.copyWith(color: AppColors.accent)),
              const SizedBox(height: 2),
              Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted, letterSpacing: 1.2),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;
  const _Row({required this.icon, required this.title, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? AppColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c))),
            Icon(Icons.chevron_right_rounded, color: (color ?? AppColors.textMuted).withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 52, color: AppColors.glassEdge);
}
