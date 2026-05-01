import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../core/session.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool showFriends = false;

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: ListView(
        children: [
          Text('Profile', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(color: const Color(0xFF56B36A), borderRadius: BorderRadius.circular(28)),
                child: Center(
                  child: Text((session.displayName.isNotEmpty ? session.displayName[0] : "A").toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(session.displayName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text('Food Explorer • Los Angeles', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted)),
                ]),
              )
            ],
          ),
          const SizedBox(height: 16),
          Row(children: const [
            Expanded(child: _StatCard(value: '12', label: 'Saved')),
            SizedBox(width: 10),
            Expanded(child: _StatCard(value: '4', label: 'Friends')),
            SizedBox(width: 10),
            Expanded(child: _StatCard(value: '28', label: 'Visited')),
          ]),
          const SizedBox(height: 16),
          _Segment(
            left: 'Account',
            right: 'Friends',
            leftActive: !showFriends,
            onLeft: () => setState(() => showFriends = false),
            onRight: () => setState(() => showFriends = true),
          ),
          const SizedBox(height: 16),
          if (!showFriends) ...[
            _SettingsRow(title: 'Dietary Preferences', onTap: () {}),
            _SettingsRow(title: 'Location Settings', onTap: () {}),
            _SettingsRow(title: 'Notification Settings', onTap: () {}),
            _SettingsRow(title: 'Privacy & Data', onTap: () {}),
            _SettingsRow(title: 'Help & Support', onTap: () {}),
            _SettingsRow(
              title: 'Sign Out',
              titleColor: const Color(0xFFFF6B6B),
              onTap: () {
                session.signOut();
                context.go(AppRoutes.signIn);
              },
            ),
          ] else ...[
            for (final f in const [('Jordan K.', '4 bookmarks shared'), ('Maya L.', '4 bookmarks shared'), ('Chris T.', '4 bookmarks shared'), ('Sam P.', '4 bookmarks shared')])
              _FriendRow(name: f.$1, subtitle: f.$2),
          ]
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
      ),
      child: Column(children: [
        Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: const Color(0xFF56B36A), fontWeight: FontWeight.w800)),
        Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted)),
      ]),
    );
  }
}

class _Segment extends StatelessWidget {
  final String left;
  final String right;
  final bool leftActive;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  const _Segment({required this.left, required this.right, required this.leftActive, required this.onLeft, required this.onRight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.48)),
      ),
      child: Row(children: [
        Expanded(child: _SegButton(label: left, active: leftActive, onTap: onLeft)),
        Expanded(child: _SegButton(label: right, active: !leftActive, onTap: onRight)),
      ]),
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegButton({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: active ? const Color(0xFF56B36A) : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? Colors.white : AppColors.textMuted, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String title;
  final Color? titleColor;
  final VoidCallback onTap;
  const _SettingsRow({required this.title, required this.onTap, this.titleColor});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.48)),
          ),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: titleColor ?? AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final String name;
  final String subtitle;
  const _FriendRow({required this.name, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.48)),
        ),
        child: Row(children: [
          Text((name.isNotEmpty ? name[0] : "?"), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: const Color(0xFF56B36A), fontWeight: FontWeight.w800)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted)),
            ]),
          ),
          Icon(Icons.group_outlined, color: AppColors.textMuted.withValues(alpha: 0.85)),
        ]),
      ),
    );
  }
}
