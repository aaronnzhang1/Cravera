import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_colors.dart';
import '../core/session.dart';
import '../models/restaurant.dart';
import '../services/location_service.dart';
import '../widgets/cravio_pulse_logo.dart';

enum _HomeView { idle, loading, result }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _promptController = TextEditingController();
  final _repromptController = TextEditingController();

  _HomeView _view = _HomeView.idle;
  int _rejectionCount = 0;
  Restaurant? _currentResult;
  bool _showRepromptBanner = false;

  @override
  void initState() {
    super.initState();
    // Ask for the device location once, after the first frame (the session
    // isn't reachable from context before then).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = AppSessionScope.of(context);
      if (session.searchLocation == null && session.locationProblem == null) {
        session.useDeviceLocation();
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _repromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    return switch (_view) {
      _HomeView.idle    => _buildIdle(context, session),
      _HomeView.loading => _buildLoading(context),
      _HomeView.result  => _buildResult(context, session),
    };
  }

  Widget _buildIdle(BuildContext context, AppSession session) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CravioPulseLogo(size: 36),
                    const SizedBox(width: 10),
                    Text('cravio', style: text.headlineSmall),
                  ],
                ),
                const Spacer(flex: 2),
                Text(
                  'Hi ${session.displayName},',
                  style: text.titleMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text('What are you\ncraving today?', style: text.displaySmall?.copyWith(height: 1.05)),
                const SizedBox(height: 10),
                Text(
                  "Describe it in your own words. I'll find one place that's open now.",
                  style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                ),
                const Spacer(flex: 3),
                _QuickPicks(
                  onPick: (craving) {
                    _promptController.text = craving;
                    _startSearch(craving);
                  },
                ),
                const SizedBox(height: 12),
                _LocationBar(
                  session: session,
                  onChange: () => _askForPlace(session),
                ),
                const SizedBox(height: 4),
                _PromptInput(
                  controller: _promptController,
                  isBusy: false,
                  onSend: () => _startSearch(_promptController.text.trim()),
                  onManualFilter: _openFilterSheet,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return PopScope(
      canPop: false,
      child: const Center(child: _LoadingView()),
    );
  }

  Widget _buildResult(BuildContext context, AppSession session) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: _InlineRestaurantCard(
                    restaurant: _currentResult!,
                    prompt: _promptController.text.trim(),
                    onNo: _onNo,
                    onYes: _onYes,
                    session: session,
                  ),
                ),
              ),
              if (_showRepromptBanner) ...[
                const SizedBox(height: 8),
                _RepromptBanner(
                  controller: _repromptController,
                  onSubmit: _onReprompt,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startSearch(String prompt) async {
    if (_view == _HomeView.loading || prompt.isEmpty) return;
    final session = AppSessionScope.of(context);
    if (session.searchLocation == null) {
      final gotPlace = await _askForPlace(session);
      if (!gotPlace || !mounted) return;
    }

    setState(() {
      _view = _HomeView.loading;
      _showRepromptBanner = false;
    });

    await Future<void>.delayed(const Duration(milliseconds: 2700));
    if (!mounted) return;

    final items = session.suggestedRestaurants;
    if (items.isEmpty) {
      setState(() => _view = _HomeView.idle);
      return;
    }

    final restaurant = items[_rejectionCount % max(1, items.length)];
    setState(() {
      _currentResult = restaurant;
      _view = _HomeView.result;
    });
  }

  Future<void> _onNo() async {
    _rejectionCount++;
    final showBanner = _rejectionCount >= 3;

    setState(() {
      _view = _HomeView.loading;
      _showRepromptBanner = showBanner;
      _currentResult = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 2700));
    if (!mounted) return;

    final session = AppSessionScope.of(context);
    final items = session.suggestedRestaurants;
    final restaurant = items[_rejectionCount % max(1, items.length)];
    setState(() {
      _currentResult = restaurant;
      _view = _HomeView.result;
    });
  }

  void _onReprompt(String extra) {
    if (extra.trim().isEmpty) return;
    final original = _promptController.text.trim();
    _rejectionCount = 0;
    _repromptController.clear();
    _startSearch('$original – ${extra.trim()}');
  }

  void _onYes() {
    if (_currentResult == null) return;
    _showNavOptions(context, _currentResult!);
  }

  /// Lets the user pick where to search: a typed place, or the device
  /// location again. Returns true once a location is set.
  Future<bool> _askForPlace(AppSession session) async {
    final choice = await showDialog<_PlaceChoice>(
      context: context,
      builder: (_) => _PlaceDialog(offerDeviceLocation: session.searchLocation?.label != 'Near you'),
    );
    if (choice == null || !mounted) return false;
    if (choice.useDevice) {
      final before = session.searchLocation;
      await session.useDeviceLocation();
      final problem = session.locationProblem;
      if (problem != null && mounted) {
        // Say so, because the bar may still show an earlier typed place.
        final keeping = before != null ? ' Still searching: ${before.label}.' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_LocationBar.problemText(problem)}$keeping')),
        );
      }
      return session.searchLocation != null;
    }
    final place = choice.place.trim();
    if (place.isEmpty) return false;
    final found = await session.useTypedPlace(place);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't find '$place'. Try a fuller address or a city name.")),
      );
    }
    return found;
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FilterSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading view — full screen, no auto-dismiss
// ---------------------------------------------------------------------------

class _LoadingView extends StatefulWidget {
  const _LoadingView();
  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView> {
  static const _messages = [
    'Hold on while I look…',
    'Scanning nearby favorites…',
    'Matching your craving…',
  ];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _cycle();
  }

  Future<void> _cycle() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CravioPulseLogo(),
        const SizedBox(height: 32),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            _messages[_index],
            key: ValueKey(_messages[_index]),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline restaurant card (replaces the bottom sheet)
// ---------------------------------------------------------------------------

class _InlineRestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final String prompt;
  final VoidCallback onNo;
  final VoidCallback onYes;
  final AppSession session;

  const _InlineRestaurantCard({
    required this.restaurant,
    required this.prompt,
    required this.onNo,
    required this.onYes,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final saved = session.isBookmarked(restaurant.placeId);


    final distanceLabel = restaurant.distanceMeters == null
        ? null
        : '${(restaurant.distanceMeters! / 1000).toStringAsFixed(1)} km';

    final text = Theme.of(context).textTheme;
    final hasAddress = (restaurant.address ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text("Here's your pick", style: text.titleMedium?.copyWith(color: AppColors.textMuted)),
            ),
            IconButton(
              onPressed: onNo,
              icon: const Icon(Icons.close_rounded),
              color: AppColors.textSecondary,
              tooltip: 'Back to search',
            ),
          ],
        ),
        if (prompt.trim().isNotEmpty) ...[
          _Pill(icon: Icons.auto_awesome_rounded, label: prompt.trim(), color: AppColors.accent),
          const SizedBox(height: 14),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _PhotoHeader(photoUrl: restaurant.photoUrl),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _RoundIcon(
                      icon: saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                      color: saved ? AppColors.accent : AppColors.textPrimary,
                      tooltip: saved ? 'Remove bookmark' : 'Bookmark',
                      onPressed: () => session.toggleBookmark(restaurant),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (restaurant.rating != null)
                          _Pill(
                            icon: Icons.star_rounded,
                            label: restaurant.rating!.toStringAsFixed(1),
                            color: AppColors.gold,
                          ),
                        if ((restaurant.cuisine ?? '').trim().isNotEmpty)
                          _Pill(icon: Icons.restaurant_rounded, label: restaurant.cuisine!.trim()),
                        if (restaurant.priceLevel != null)
                          _Pill(label: '\$' * restaurant.priceLevel!.clamp(1, 4)),
                        if (distanceLabel != null)
                          _Pill(icon: Icons.near_me_rounded, label: distanceLabel, color: AppColors.sage),
                      ],
                    ),
                    if (hasAddress) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined, size: 18, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              restaurant.address!.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onNo,
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('No'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: onYes,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Yes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Location bar — where searches happen, with a way to change it
// ---------------------------------------------------------------------------

class _LocationBar extends StatelessWidget {
  final AppSession session;
  final VoidCallback onChange;
  const _LocationBar({required this.session, required this.onChange});

  static String problemText(LocationProblem problem) => switch (problem) {
        LocationProblem.serviceOff => 'Location is off on this device.',
        LocationProblem.denied => 'Location permission was denied.',
        LocationProblem.deniedForever => 'Location is blocked in settings.',
        LocationProblem.failed => "Couldn't get your location.",
      };

  @override
  Widget build(BuildContext context) {
    final location = session.searchLocation;
    final problem = session.locationProblem;

    final String text;
    if (session.isLocating) {
      text = 'Finding your location…';
    } else if (location != null) {
      text = 'Searching: ${location.label}';
    } else if (problem != null) {
      text = '${problemText(problem)} Type a place instead.';
    } else {
      text = 'No location yet.';
    }

    return Row(
      children: [
        Icon(
          location != null ? Icons.place_rounded : Icons.location_off_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: session.isLocating ? null : onChange,
          child: const Text('Change'),
        ),
      ],
    );
  }
}

/// What the user picked in the place dialog.
class _PlaceChoice {
  final String place;
  final bool useDevice;
  const _PlaceChoice.typed(this.place) : useDevice = false;
  const _PlaceChoice.device()
      : place = '',
        useDevice = true;
}

class _PlaceDialog extends StatefulWidget {
  final bool offerDeviceLocation;
  const _PlaceDialog({required this.offerDeviceLocation});
  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_PlaceChoice.typed(_controller.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Where should I search?'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'An address, neighborhood or city'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (widget.offerDeviceLocation)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const _PlaceChoice.device()),
            child: const Text('Use my location'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Search here'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reprompt banner — appears after 3 rejections
// ---------------------------------------------------------------------------

class _RepromptBanner extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  const _RepromptBanner({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Want to narrow it down? Tell me more…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'e.g. outdoor seating, no seafood',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: onSubmit,
                ),
              ),
              const SizedBox(width: 8),
              _IconAction(
                tooltip: 'Search again',
                icon: Icons.arrow_upward_rounded,
                onPressed: () => onSubmit(controller.text),
                filled: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter sheet
// ---------------------------------------------------------------------------

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _cuisines = [
    'Italian', 'Japanese', 'Mexican', 'Indian',
    'Mediterranean', 'American', 'Thai', 'Chinese',
  ];
  final Set<String> _selectedCuisines = {};
  int _priceLevel = 0;
  double _distanceKm = 5.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.border.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Text('Cuisine', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cuisines.map((c) {
              final selected = _selectedCuisines.contains(c);
              return FilterChip(
                label: Text(c),
                selected: selected,
                onSelected: (v) => setState(() => v ? _selectedCuisines.add(c) : _selectedCuisines.remove(c)),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Text('Price', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final level in [0, 1, 2, 3, 4])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(level == 0 ? 'Any' : '\$' * level),
                    selected: _priceLevel == level,
                    onSelected: (_) => setState(() => _priceLevel = level),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Distance', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
              const Spacer(),
              Text(
                '${_distanceKm.toStringAsFixed(0)} km',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          Slider(
            value: _distanceKm,
            min: 1,
            max: 30,
            divisions: 29,
            onChanged: (v) => setState(() => _distanceKm = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation options sheet (Yes path)
// ---------------------------------------------------------------------------

Future<void> _showNavOptions(BuildContext context, Restaurant restaurant) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.navigation_rounded),
              title: const Text('Navigate there'),
              subtitle: const Text('Open directions in your maps app'),
              onTap: () async {
                Navigator.of(context).pop();
                await _openNavigation(context, restaurant);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Close for now'),
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _openNavigation(BuildContext context, Restaurant restaurant) async {
  final encoded = Uri.encodeComponent(restaurant.name);
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!context.mounted) return;
  if (!launched) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open navigation app.')),
    );
  }
}

// ---------------------------------------------------------------------------
// Prompt input bar: one rounded composer with filter, mic and send
// ---------------------------------------------------------------------------

class _PromptInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback? onManualFilter;
  const _PromptInput({required this.controller, required this.isBusy, required this.onSend, this.onManualFilter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _IconAction(
            icon: Icons.tune_rounded,
            tooltip: 'Filters',
            onPressed: onManualFilter ?? () {},
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Type your craving…',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              ),
            ),
          ),
          _IconAction(
            icon: Icons.mic_none_rounded,
            tooltip: 'Voice (coming soon)',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice input coming soon')),
              );
            },
          ),
          const SizedBox(width: 4),
          _IconAction(
            icon: Icons.arrow_upward_rounded,
            tooltip: 'Search',
            onPressed: onSend,
            filled: true,
            disabled: isBusy,
          ),
        ],
      ),
    );
  }
}

/// One-tap example cravings, for when you don't know what to type.
class _QuickPicks extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _QuickPicks({required this.onPick});

  static const _picks = [
    ('🍜', 'Ramen'),
    ('🌮', 'Tacos'),
    ('🍕', 'Pizza'),
    ('🍣', 'Sushi'),
    ('🍔', 'Burgers'),
    ('🥗', 'Something healthy'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _picks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (emoji, label) = _picks[i];
          return ActionChip(
            avatar: Text(emoji, style: const TextStyle(fontSize: 16)),
            label: Text(label),
            onPressed: () => onPick(label),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;
  final bool disabled;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: disabled ? null : onPressed,
        style: IconButton.styleFrom(
          backgroundColor: filled ? AppColors.accent : Colors.transparent,
          foregroundColor: filled ? AppColors.onAccent : AppColors.textSecondary,
          disabledBackgroundColor: AppColors.surface3,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

/// A small rounded label with an optional icon, used for restaurant facts.
class _Pill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;
  const _Pill({this.icon, required this.label, this.color = AppColors.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  final String? photoUrl;
  const _PhotoHeader({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;
    return SizedBox(
      height: 210,
      width: double.infinity,
      child: hasPhoto
          ? Image.network(photoUrl!, fit: BoxFit.cover)
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.accentSoft, AppColors.surface2],
                ),
              ),
              child: const Center(
                child: Icon(Icons.ramen_dining_rounded, color: AppColors.textMuted, size: 56),
              ),
            ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;
  const _RoundIcon({required this.icon, required this.color, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.background.withValues(alpha: 0.7),
        foregroundColor: color,
      ),
      icon: Icon(icon),
    );
  }
}
