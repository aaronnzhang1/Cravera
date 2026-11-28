import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_colors.dart';
import '../widgets/glass.dart';

/// A preview of what friends will do in Cravera (TASK-UI-3), with an invite.
/// No people are listed: real friends come in a later task.
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  /// Opens the system share sheet with [text]. Tests replace it.
  @visibleForTesting
  static Future<void> Function(String text) shareText =
      (text) => SharePlus.instance.share(ShareParams(text: text));

  /// What Invite shares. No link yet: the app isn't in a store.
  static const inviteText =
      'I’m using Cravera: tell it what you’re craving and it picks one open place nearby. Want to try it with me?';

  static const _features = [
    (Icons.ios_share_rounded, 'Share a pick', 'Send the place you found to a friend in one tap.'),
    (Icons.place_outlined, 'See where friends eat', 'Their been-there spots, on your map.'),
    (Icons.groups_2_outlined, 'Decide together', 'Pick somewhere open that works for everyone.'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      // Bottom padding clears the floating nav bar.
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        const PageHeader(
          title: 'Friends',
          subtitle: 'Food is better shared.',
        ),
        Glass(
          tint: AppColors.accent,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AvatarStack(),
              const SizedBox(height: 16),
              Text('Bring your people', style: text.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Friends are coming to Cravera. Invite the people you eat with now, so they’re here when it opens.',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _invite(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Invite a friend'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
          child: Text(
            'COMING WITH FRIENDS',
            style: text.labelMedium?.copyWith(color: AppColors.textMuted, letterSpacing: 1.2),
          ),
        ),
        Glass(
          child: Column(
            children: [
              for (var i = 0; i < _features.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 68, color: AppColors.glassEdge),
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                          child: Icon(_features[i].$1, size: 20, color: AppColors.accent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_features[i].$2, style: text.titleMedium),
                              const SizedBox(height: 2),
                              Text(_features[i].$3, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the share sheet; if sharing isn't available, copies the invite.
  Future<void> _invite(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await shareText(inviteText);
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: inviteText));
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Invite copied. Paste it in a message to a friend.')));
    }
  }
}

/// Three overlapping circles: a group, without pretending to be real people.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack();

  static const _icons = [Icons.ramen_dining_rounded, Icons.local_pizza_rounded, Icons.lunch_dining_rounded];
  static const _colors = [AppColors.accentLight, AppColors.sage, AppColors.accentPressed];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 48,
        width: 48 + 2 * 32,
        child: Stack(
          children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: i * 32.0,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _colors[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 3),
                  ),
                  child: Icon(_icons[i], color: AppColors.onAccent, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
