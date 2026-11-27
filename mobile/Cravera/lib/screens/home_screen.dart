import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_colors.dart';
import '../core/session.dart';
import '../models/restaurant.dart';
import '../services/craving_search.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../widgets/cravera_logo.dart';
import '../widgets/floating_cards.dart';
import '../widgets/glass.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _promptController = TextEditingController();
  final _repromptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Ask for the device location once, after the first frame (the session
    // isn't reachable from context before then).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = AppSessionScope.of(context);
      if (session.searchLocation == null && session.locationProblem == null) {
        session.useDeviceLocation();
      }
      // Coming back to Home later: results that may have closed are dropped.
      session.search.checkFresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptController.dispose();
    _repromptController.dispose();
    super.dispose();
  }

  /// Back from the background: results that may have closed are dropped.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) AppSessionScope.of(context).search.checkFresh();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final search = session.search;
    return switch (search.status) {
      SearchStatus.idle => _buildIdle(context, session),
      SearchStatus.loading => _buildLoading(context),
      // An expired card is never drawn, even before the next check runs.
      SearchStatus.showing => search.isFresh ? _buildResult(context, session) : _buildOutcome(context, search),
      SearchStatus.exhausted || SearchStatus.failed || SearchStatus.expired => _buildOutcome(context, search),
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
                    restaurant: session.search.current!,
                    prompt: session.search.query,
                    onNo: session.search.next,
                    onYes: _onYes,
                    onClose: session.search.reset,
                    photo: session.search.currentPhoto,
                    session: session,
                  ),
                ),
              ),
              if (session.search.rejections >= 3) ...[
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
    if (prompt.isEmpty || AppSessionScope.of(context).search.status == SearchStatus.loading) return;
    final session = AppSessionScope.of(context);
    if (session.locationChanging) {
      // Searching now would use the area the user is leaving.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still finding your location. Try again in a moment.')),
      );
      return;
    }
    if (session.searchLocation == null) {
      final gotPlace = await _askForPlace(session);
      if (!gotPlace || !mounted) return;
    }

    final near = session.searchLocation;
    if (near == null) return;
    await session.search.start(prompt, near);
  }

  /// Adds the user's extra words to the craving and searches again.
  void _onReprompt(String extra) {
    if (extra.trim().isEmpty) return;
    _repromptController.clear();
    final search = AppSessionScope.of(context).search;
    search.refine(extra).then((_) {
      if (mounted) _promptController.text = search.query;
    });
  }

  void _onYes() {
    final session = AppSessionScope.of(context);
    final search = session.search;
    // Never send someone to a place based on an old "open now", or while
    // the search area is changing.
    if (session.locationChanging || !search.checkFresh()) return;
    final current = search.current;
    if (current == null) return;
    _showNavOptions(context, current, search);
  }

  /// Out of results, nothing found, or a failed search: say which, and offer
  /// the next step (refine, try again, or start over).
  Widget _buildOutcome(BuildContext context, CravingSearch search) {
    final text = Theme.of(context).textTheme;
    final failed = search.status == SearchStatus.failed;
    final expired = search.status == SearchStatus.expired || !search.isFresh;
    final (title, detail) = expired
        ? ('These results are out of date.', 'Places may have closed since. Search again to see what is open now.')
        : search.queryTooLong
            ? ('That craving is too long.', 'Keep it under ${CravingSearch.maxQueryLength} characters and search again.')
            : failed
                ? searchErrorText(search.error ?? PlacesSearchError.server)
                : search.foundNothing
                    ? ('Nothing open matched “${search.query}” nearby.', 'Try different words, or add more detail.')
                    : ("That's every open match for “${search.query}” nearby.", 'Add something to narrow or change it.');
    // Retrying only helps when the request itself was fine.
    final canRetry = expired || (failed && search.error != PlacesSearchError.rejected);
    return SafeArea(
      child: Center(
        // Scrolls on short phones when the keyboard opens to refine.
        child: SingleChildScrollView(
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  expired
                      ? Icons.schedule_rounded
                      : failed
                          ? Icons.cloud_off_rounded
                          : Icons.search_off_rounded,
                  size: 48,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 16),
                Text(title, textAlign: TextAlign.center, style: text.titleLarge),
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                if (canRetry)
                  FilledButton.icon(
                    onPressed: search.retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(expired ? 'Search again' : 'Try again'),
                  )
                else if (!failed)
                  _RepromptBanner(controller: _repromptController, onSubmit: _onReprompt),
                const SizedBox(height: 8),
                TextButton(onPressed: search.reset, child: const Text('New search')),
              ],
            ),
          ),
          ),
        ),
      ),
    );
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
  final VoidCallback onClose;
  final Uint8List? photo;
  final AppSession session;

  const _InlineRestaurantCard({
    required this.restaurant,
    required this.prompt,
    required this.onNo,
    required this.onYes,
    required this.onClose,
    required this.photo,
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
              onPressed: onClose,
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
                  _PhotoHeader(photo: photo),
                  // Google requires the photo author's credit with the photo.
                  if (photo != null && restaurant.photoAuthor != null)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      right: 70,
                      child: _PhotoCredit(author: restaurant.photoAuthor!, uri: restaurant.photoAuthorUri),
                    ),
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
                    // Why this pick: the guest's own wants this place matches.
                    // The facts beside it (rating, price, distance) come from Places.
                    if (restaurant.matches.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Picked for: ${restaurant.matches.join(' · ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: AppColors.accent),
                      ),
                    ],
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
                        if (priceLabel(restaurant.priceLevel) case final price?) _Pill(label: price),
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
                    const SizedBox(height: 8),
                    // Places data shown outside a Google map needs this credit.
                    Text('Google Maps', style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                    const SizedBox(height: 14),
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

/// Google's price level as shown on the card: 0 is free, 1–4 are dollar
/// signs, anything else (or nothing) shows no price.
String? priceLabel(int? level) => switch (level) {
  0 => 'Free',
  1 || 2 || 3 || 4 => '\$' * level!,
  _ => null,
};

/// What to tell the user when a search fails: a title and what to do next.
(String, String) searchErrorText(PlacesSearchError error) => switch (error) {
  PlacesSearchError.network => ('No connection.', 'Check your internet, then try again.'),
  PlacesSearchError.server => ("Search isn't working right now.", 'Try again in a moment.'),
  PlacesSearchError.notConfigured => ("Search isn't set up in this app.", 'Try again, or reinstall the app.'),
  PlacesSearchError.rejected => ('Something went wrong with that search.', 'Try again.'),
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

Future<void> _showNavOptions(BuildContext context, Restaurant restaurant, CravingSearch search) {
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
                // The sheet may have been open a while: check again that this
                // is still the current, fresh result before opening Maps.
                if (!search.checkFresh() || search.current?.placeId != restaurant.placeId) return;
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

/// Directions to this exact place: its coordinates as the destination and its
/// Google place ID, never a search by name (which could pick another branch).
/// Null when the place has no coordinates.
Uri? directionsUri(Restaurant restaurant) {
  final lat = restaurant.latitude;
  final lng = restaurant.longitude;
  if (lat == null || lng == null) return null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$lat,$lng',
    'destination_place_id': restaurant.placeId,
  });
}

Future<void> _openNavigation(BuildContext context, Restaurant restaurant) async {
  final uri = directionsUri(restaurant);
  final launched = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);

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
  /// Already downloaded by [PlacesService.photoBytes], so nothing here goes
  /// to the network. Null shows the placeholder.
  final Uint8List? photo;
  const _PhotoHeader({required this.photo});

  @override
  Widget build(BuildContext context) {
    final bytes = photo;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentSoft, AppColors.surface2],
        ),
      ),
      child: const Center(child: Icon(Icons.restaurant_rounded, color: AppColors.textMuted, size: 56)),
    );
    return SizedBox(
      height: 210,
      width: double.infinity,
      child: bytes == null
          ? placeholder
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Bytes that aren't a valid image show the placeholder.
              errorBuilder: (context, error, stack) => placeholder,
            ),
    );
  }
}

/// "Photo: [author]" over the photo, linking to the author's page when Google
/// gives one (https only).
class _PhotoCredit extends StatelessWidget {
  final String author;
  final String? uri;
  const _PhotoCredit({required this.author, required this.uri});

  @override
  Widget build(BuildContext context) {
    final link = uri == null ? null : Uri.tryParse(uri!);
    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Photo: $author',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textPrimary,
              decoration: link == null ? null : TextDecoration.underline,
            ),
      ),
    );
    if (link == null) return Align(alignment: Alignment.bottomLeft, child: label);
    return Align(
      alignment: Alignment.bottomLeft,
      child: Semantics(
        link: true,
        child: InkWell(
          onTap: () => launchUrl(link, mode: LaunchMode.externalApplication),
          child: label,
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
      style: IconButton.styleFrom(backgroundColor: AppColors.background.withValues(alpha: 0.7), foregroundColor: color),
      icon: Icon(icon),
    );
  }
}
