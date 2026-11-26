import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_colors.dart';
import '../core/session.dart';
import '../models/restaurant.dart';
import '../services/location_service.dart';
import '../widgets/cravera_logo.dart';
import '../widgets/floating_cards.dart';
import '../widgets/glass.dart';

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
      _HomeView.idle => _buildIdle(context, session),
      _HomeView.loading => _buildLoading(context),
      _HomeView.result => _buildResult(context, session),
    };
  }

  Widget _buildIdle(BuildContext context, AppSession session) {
    final text = Theme.of(context).textTheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        const FloatingCards(),
        // Fade the drifting cards out toward the bottom, so the suggestions
        // and the composer always sit on a calm background.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0),
                  AppColors.background.withValues(alpha: 0.6),
                  AppColors.background,
                ],
                stops: const [0.0, 0.55, 0.8],
              ),
            ),
          ),
        ),
        SafeArea(
          // The floating nav sits behind the keyboard while typing, so don't
          // keep room for it then.
          bottom: View.of(context).viewInsets.bottom == 0,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Short screens (such as iPhone SE) get a smaller orb and no subtitle.
                    final compact = box.maxHeight < 640;
                    // While typing, drop the orb and greeting so the composer always
                    // fits above the keyboard, even on short phones.
                    // Read the keyboard from the view: Scaffold hides it from the body's MediaQuery.
                    final typing = View.of(context).viewInsets.bottom > 0;
                    return Column(
                      children: [
                        Row(
                          children: [
                            Text('Cravera', style: text.headlineSmall),
                            const SizedBox(width: 12),
                            // The chip takes what's left, so a long place or large text ellipsizes instead of overflowing.
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _LocationChip(session: session, onTap: () => _askForPlace(session)),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (!typing) ...[
                        CraveraLogo(size: compact ? 56 : 88),
                        SizedBox(height: compact ? 14 : 22),
                        Text(
                          '${_greeting()}, ${session.displayName}',
                          textAlign: TextAlign.center,
                          style: text.titleMedium?.copyWith(color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'What are you\ncraving today?',
                          textAlign: TextAlign.center,
                          style: text.displaySmall?.copyWith(height: 1.05),
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 10),
                          Text(
                            "Say it your way. I'll find one spot that's open now.",
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                        ],
                        const Spacer(),
                        _LocationProblemBanner(session: session, onFix: () => _askForPlace(session)),
                        _QuickPicks(
                          onPick: (craving) {
                            _promptController.text = craving;
                            _startSearch(craving);
                          },
                        ),
                        const SizedBox(height: 12),
                        _PromptInput(
                          controller: _promptController,
                          isBusy: false,
                          onSend: () => _startSearch(_promptController.text.trim()),
                          onManualFilter: _openFilterSheet,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildLoading(BuildContext context) {
    return PopScope(canPop: false, child: const Center(child: _LoadingView()));
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
                _RepromptBanner(controller: _repromptController, onSubmit: _onReprompt),
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
        // Never echo the place: messages can outlive the screen (even sign out).
        final keeping = before != null ? ' Still searching the place you set.' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${locationProblemText(problem)}$keeping')));
      }
      return session.searchLocation != null;
    }
    final place = choice.place.trim();
    if (place.isEmpty) return false;
    final found = await session.useTypedPlace(place);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't find that place. Try a fuller address or a city name.")),
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

/// Shows the concierge working through its steps, so the wait explains itself.
class _LoadingViewState extends State<_LoadingView> {
  static const _steps = ['Understanding your craving', "Checking what's open nearby", 'Choosing your best match'];
  int _done = 0;

  @override
  void initState() {
    super.initState();
    _advance();
  }

  Future<void> _advance() async {
    while (mounted && _done < _steps.length) {
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
      setState(() => _done++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CraveraLogo(size: 112, thinking: true),
          const SizedBox(height: 36),
          Text('On it…', style: text.headlineSmall),
          const SizedBox(height: 20),
          for (var i = 0; i < _steps.length; i++)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pending steps use the muted text color, which still meets AA contrast.
                    SizedBox.square(
                      dimension: 20,
                      child: i < _done
                          ? const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.sage)
                          : i == _done
                          // Reduce Motion: a still icon instead of a spinner.
                          ? (MediaQuery.disableAnimationsOf(context)
                                ? const Icon(Icons.radio_button_checked_rounded, size: 20, color: AppColors.accent)
                                : const CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                          : const Icon(Icons.circle_outlined, size: 20, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 12),
                    // Flexible lets a long step wrap on narrow phones with large text.
                    Flexible(
                      child: Text(
                        _steps[i],
                        style: text.bodyLarge?.copyWith(color: i <= _done ? AppColors.textSecondary : AppColors.textMuted),
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
            const CraveraLogo(size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text("Cravera's pick", style: text.titleMedium)),
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
                    Text(restaurant.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.headlineMedium),
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
                        if (restaurant.priceLevel != null) _Pill(label: '\$' * restaurant.priceLevel!.clamp(1, 4)),
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

String locationProblemText(LocationProblem problem) => switch (problem) {
  LocationProblem.serviceOff => 'Location is off on this device.',
  LocationProblem.denied => 'Location permission was denied.',
  LocationProblem.deniedForever => 'Location is blocked in settings.',
  LocationProblem.failed => "Couldn't get your location.",
};

/// A small glass pill showing where searches happen. Tap it to change.
class _LocationChip extends StatelessWidget {
  final AppSession session;
  final VoidCallback onTap;
  const _LocationChip({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final location = session.searchLocation;
    final label = session.isLocating ? 'Locating…' : (location?.label ?? 'Set location');
    return Tooltip(
      message: 'Change location',
      child: Glass(
        radius: 999,
        child: InkWell(
          onTap: session.isLocating ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  location != null ? Icons.near_me_rounded : Icons.location_off_rounded,
                  size: 16,
                  color: location != null ? AppColors.sage : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains a location problem above the composer, with a way to fix it.
class _LocationProblemBanner extends StatelessWidget {
  final AppSession session;
  final VoidCallback onFix;
  const _LocationProblemBanner({required this.session, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final problem = session.locationProblem;
    if (problem == null || session.searchLocation != null || session.isLocating) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            const Icon(Icons.location_off_rounded, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${locationProblemText(problem)} Type a place instead.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            TextButton(onPressed: onFix, child: const Text('Set place')),
          ],
        ),
      ),
    );
  }
}

/// What the user picked in the place dialog.
class _PlaceChoice {
  final String place;
  final bool useDevice;
  const _PlaceChoice.typed(this.place) : useDevice = false;
  const _PlaceChoice.device() : place = '', useDevice = true;
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'A city, neighborhood or address'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          // Say where the text goes before it is sent (Android's geocoder may use the network).
          Text(
            "A city or neighborhood works fine. Your phone's map service looks up what you type.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        if (widget.offerDeviceLocation)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const _PlaceChoice.device()),
            child: const Text('Use my location'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Search here')),
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
  static const _cuisines = ['Italian', 'Japanese', 'Mexican', 'Indian', 'Mediterranean', 'American', 'Thai', 'Chinese'];
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
              Text(
                'Distance',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              Text(
                '${_distanceKm.toStringAsFixed(0)} km',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          Slider(value: _distanceKm, min: 1, max: 30, divisions: 29, onChanged: (v) => setState(() => _distanceKm = v)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Apply Filters')),
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
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open navigation app.')));
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.18), blurRadius: 28)],
      ),
      child: Glass(
        blur: true,
        radius: 999,
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 22),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask Cravera…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                ),
              ),
            ),
            _IconAction(icon: Icons.tune_rounded, tooltip: 'Filters', onPressed: onManualFilter ?? () {}),
            _IconAction(
              icon: Icons.mic_none_rounded,
              tooltip: 'Voice (coming soon)',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice input coming soon')));
              },
            ),
            const SizedBox(width: 2),
            _IconAction(
              icon: Icons.arrow_upward_rounded,
              tooltip: 'Search',
              onPressed: onSend,
              filled: true,
              disabled: isBusy,
            ),
          ],
        ),
      ),
    );
  }
}

/// Example requests in plain language, to show what the concierge understands.
class _QuickPicks extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _QuickPicks({required this.onPick});

  static const _picks = [
    ('🍜', 'Cozy ramen nearby'),
    ('🌮', 'Tacos, open late'),
    ('🥗', 'Something healthy'),
    ('🍣', 'Date-night sushi'),
    ('🍔', 'A really good burger'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        // Chips scroll out to the screen edge instead of being cut at the margin.
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: _picks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (emoji, label) = _picks[i];
          return Glass(
            radius: 999,
            child: InkWell(
              onTap: () => onPick(label),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ),
            ),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 6)],
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
              child: const Center(child: Icon(Icons.ramen_dining_rounded, color: AppColors.textMuted, size: 56)),
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
      style: IconButton.styleFrom(backgroundColor: AppColors.background.withValues(alpha: 0.7), foregroundColor: color),
      icon: Icon(icon),
    );
  }
}
