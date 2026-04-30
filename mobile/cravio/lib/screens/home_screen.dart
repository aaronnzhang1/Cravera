import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              children: [
                const SizedBox(height: 16),
                _LogoMark(),
                const SizedBox(height: 18),
                Text(
                  'cravio.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'your AI food concierge',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 28),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'What are you craving?',
                    prefixIcon: const Icon(Icons.search_rounded),
                    prefixIconColor: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.go(AppRoutes.results),
                    child: const Text('Find me a place'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.go(AppRoutes.signIn),
                        child: const Text('Sign in'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.go(AppRoutes.signUp),
                        child: const Text('Sign up'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _QuickLink(
                      label: 'Profile',
                      icon: Icons.person_outline_rounded,
                      onPressed: () => context.go(AppRoutes.profile),
                    ),
                    _QuickLink(
                      label: 'Bookmarks',
                      icon: Icons.bookmark_outline_rounded,
                      onPressed: () => context.go(AppRoutes.bookmarks),
                    ),
                    _QuickLink(
                      label: 'Friends',
                      icon: Icons.group_outlined,
                      onPressed: () => context.go(AppRoutes.friends),
                    ),
                    _QuickLink(
                      label: 'Recs inbox',
                      icon: Icons.inbox_outlined,
                      onPressed: () => context.go(AppRoutes.recs),
                    ),
                    _QuickLink(
                      label: 'Navigate',
                      icon: Icons.map_outlined,
                      onPressed: () => context.go(AppRoutes.navigate),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 44,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _QuickLink({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.55), width: 1.5),
      ),
    );
  }
}
