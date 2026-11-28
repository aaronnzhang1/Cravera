import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../core/session.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../widgets/glass.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final text = Theme.of(context).textTheme;
    final name = session.isGuest ? 'Guest' : session.displayName;
    final rated = session.bookmarks.where((r) => session.bookmarkRating(r.placeId) > 0).length;
    final profile = session.profile;
    final canEdit = session.isSignedIn && profile != null;

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
                      // The email is in the Account section below.
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
                Text('Make Cravera yours', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Create a free account to keep your name, dietary preferences and search distance on any phone.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  // Keep the guest session (and its location) until sign-up completes.
                  onPressed: () => context.go(AppRoutes.signUp),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ],
        if (session.isSignedIn) ...[
          const _SectionLabel('Account'),
          Glass(
            child: Column(
              children: [
                _Row(
                  icon: Icons.badge_outlined,
                  title: 'Name',
                  value: profile?.displayName ?? session.displayName,
                  onTap: canEdit ? () => _editName(context, session) : null,
                ),
                const _RowDivider(),
                _Row(icon: Icons.mail_outline_rounded, title: 'Email', value: session.email ?? ''),
              ],
            ),
          ),
        ],
        const _SectionLabel('Preferences'),
        if (!canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.isGuest
                        ? 'Create an account to save preferences.'
                        : session.profileLoadFailed
                            ? 'Couldn’t load your preferences.'
                            : 'Loading your preferences…',
                    style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                if (session.isSignedIn && session.profileLoadFailed)
                  TextButton(onPressed: session.retryProfileLoad, child: const Text('Try again')),
              ],
            ),
          ),
        Glass(
          child: Column(
            children: [
              _Row(
                icon: Icons.restaurant_menu_rounded,
                title: 'Dietary preferences',
                value: profile == null ? null : _dietSummary(profile.dietaryPreferences),
                onTap: canEdit ? () => _editDiet(context, session) : null,
                enabled: canEdit,
              ),
              const _RowDivider(),
              _Row(
                icon: Icons.location_city_rounded,
                title: 'Home city',
                value: profile == null ? null : (profile.homeCity ?? 'Not set'),
                onTap: canEdit ? () => _editCity(context, session) : null,
                enabled: canEdit,
              ),
              const _RowDivider(),
              _Row(
                icon: Icons.near_me_rounded,
                title: 'Search distance',
                value: profile == null ? null : _km(profile.defaultRadiusMeters),
                onTap: canEdit ? () => _editRadius(context, session) : null,
                enabled: canEdit,
              ),
            ],
          ),
        ),
        const _SectionLabel('About'),
        Glass(
          child: _Row(icon: Icons.shield_outlined, title: 'Privacy & data', onTap: () => _showPrivacy(context)),
        ),
        const SizedBox(height: 12),
        if (session.isSignedIn) ...[
          Glass(
            child: _Row(
              icon: Icons.delete_outline_rounded,
              title: 'Delete account',
              color: AppColors.danger,
              onTap: () => _confirmDelete(context, session),
            ),
          ),
          const SizedBox(height: 12),
        ],
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

/// Asks before deleting: it can't be undone. Then deletes the account on the
/// server (the caller's own only) and returns to sign-in.
Future<void> _confirmDelete(BuildContext context, AppSession session) async {
  // The account this confirmation is for: if another one is signed in by the
  // time Delete is tapped, nothing happens.
  final account = session.accountId;
  if (account == null) return;
  final sure = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text('Your account and profile are removed for good. This can’t be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (sure != true || !context.mounted || session.accountId != account) return;
  final outcome = await session.deleteAccount(expectedAccountId: account);
  if (!context.mounted) return;
  if (outcome == AuthOutcome.ok && session.accountId == null) {
    ScaffoldMessenger.of(context).clearSnackBars();
    context.go(AppRoutes.signIn);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authMessage(outcome))));
  }
}

String _km(int meters) {
  final km = meters / 1000;
  return '${km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1)} km';
}

String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _dietSummary(List<String> diet) {
  if (diet.isEmpty) return 'None';
  final first = _capitalized(diet.first);
  return diet.length == 1 ? first : '$first +${diet.length - 1}';
}

/// Saves one edit and tells the person how it went. Only that field is
/// sent; the session drops the answer if the account changed meanwhile.
Future<void> _save(BuildContext context, AppSession session, ProfileChange change) async {
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await session.updateProfile(change);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(profileSaveMessage(outcome))));
}

/// Saves [change] once an editor closes, unless the account changed while it
/// was open (then nothing is saved onto the wrong person).
Future<void> _saveEdit(BuildContext context, AppSession session, String? account, ProfileChange change) async {
  if (!context.mounted || session.profile == null || session.accountId != account) return;
  await _save(context, session, change);
}

Future<void> _editName(BuildContext context, AppSession session) async {
  // An old "Saved." message would cover the editor's bottom option.
  ScaffoldMessenger.of(context).clearSnackBars();
  final current = session.profile;
  if (current == null) return;
  final account = session.accountId;
  final name = await _askText(context, title: 'Your name', initial: current.displayName, maxLength: Profile.maxNameLength);
  if (name == null || !context.mounted) return;
  await _saveEdit(context, session, account, ProfileChange(displayName: name));
}

Future<void> _editCity(BuildContext context, AppSession session) async {
  // An old "Saved." message would cover the editor's bottom option.
  ScaffoldMessenger.of(context).clearSnackBars();
  final current = session.profile;
  if (current == null) return;
  final account = session.accountId;
  final city = await _askText(
    context,
    title: 'Home city',
    initial: current.homeCity ?? '',
    maxLength: Profile.maxCityLength,
    hint: 'e.g. Oakland',
    allowEmpty: true,
  );
  if (city == null || !context.mounted) return;
  final trimmed = city.trim();
  await _saveEdit(context, session, account, ProfileChange(homeCity: trimmed));
}

/// A one-field dialog. Returns the text, or null if cancelled.
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String initial,
  required int maxLength,
  String? hint,
  bool allowEmpty = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, maxLength: maxLength, hint: hint, allowEmpty: allowEmpty),
    );

/// Owns its text controller, so it lives until the dialog's closing
/// animation is over (disposing it when the dialog returns is too early).
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.maxLength, this.hint, this.allowEmpty = false});
  final String title;
  final String initial;
  final int maxLength;
  final String? hint;
  final bool allowEmpty;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ok => widget.allowEmpty || _controller.text.trim().isNotEmpty;

  void _submit() {
    if (_ok) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          hintText: widget.hint,
          labelText: widget.title,
          errorText: _ok ? null : 'Enter at least one character.',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _ok ? _submit : null, child: const Text('Save')),
      ],
    );
  }
}

Future<void> _editDiet(BuildContext context, AppSession session) async {
  // An old "Saved." message would cover the editor's bottom option.
  ScaffoldMessenger.of(context).clearSnackBars();
  final current = session.profile;
  if (current == null) return;
  final account = session.accountId;
  final chosen = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final picked = {...current.dietaryPreferences};
      final text = Theme.of(sheetContext).textTheme;
      return StatefulBuilder(
        builder: (sheetContext, setState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dietary preferences', style: text.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Saved to your account. Search doesn’t use them yet.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in Profile.dietaryChoices)
                      FilterChip(
                        label: Text(_capitalized(d)),
                        selected: picked.contains(d),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (on) => setState(() => on ? picked.add(d) : picked.remove(d)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop([
                      for (final d in Profile.dietaryChoices)
                        if (picked.contains(d)) d,
                    ]),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  if (chosen == null || !context.mounted) return;
  await _saveEdit(context, session, account, ProfileChange(dietaryPreferences: chosen));
}

Future<void> _editRadius(BuildContext context, AppSession session) async {
  // An old "Saved." message would cover the editor's bottom option.
  ScaffoldMessenger.of(context).clearSnackBars();
  final current = session.profile;
  if (current == null) return;
  final account = session.accountId;
  final chosen = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text('Search distance', style: text.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'How far new searches look from your location.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              for (final m in Profile.radiusChoices)
                ListTile(
                  title: Text(_km(m)),
                  trailing: m == current.defaultRadiusMeters ? const Icon(Icons.check_rounded, color: AppColors.accent) : null,
                  selected: m == current.defaultRadiusMeters,
                  onTap: () => Navigator.of(sheetContext).pop(m),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (chosen == null || chosen == current.defaultRadiusMeters || !context.mounted) return;
  await _saveEdit(context, session, account, ProfileChange(defaultRadiusMeters: chosen));
}

void _showPrivacy(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Privacy & data'),
      content: const SingleChildScrollView(
        child: Text(
          'With an account, Cravera keeps your email, name, home city, dietary preferences and search distance. '
          'Only you can read or change them, and Delete account removes them for good.\n\n'
          'To find a place, your craving and the area you search are sent to Google (Places and Gemini). '
          'Cravera doesn’t keep your searches or your location.',
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
    ),
  );
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

  /// The current setting, shown under the title.
  final String? value;

  /// Null makes a plain row with no chevron.
  final VoidCallback? onTap;

  /// False shows a setting greyed out (guests, or while the profile loads).
  final bool enabled;
  final Color? color;
  const _Row({required this.icon, required this.title, this.value, this.onTap, this.enabled = true, this.color});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = !enabled ? AppColors.textSecondary : (color ?? AppColors.textPrimary);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? AppColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium?.copyWith(color: c)),
                  if (value != null && value!.isNotEmpty)
                    Text(value!, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: (color ?? AppColors.textMuted).withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
    // One control for screen readers: title and value read together.
    return MergeSemantics(
      child: onTap == null
          ? Semantics(enabled: enabled, child: row)
          : InkWell(onTap: onTap, child: row),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 52, color: AppColors.glassEdge);
}
