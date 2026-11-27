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
import '../widgets/glass.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _promptController = TextEditingController();
  final _repromptController = TextEditingController();

  /// The search ([CravingSearch.searchId]) the user hid "Narrow it down"
  /// for; any new search, even with the same words, can show it again.
  int? _narrowHiddenFor;

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

  /// Home: one question, the location, and one input. Nothing else competes
  /// with typing (concierge plan, TASK-UI-2).
  Widget _buildIdle(BuildContext context, AppSession session) {
    final text = Theme.of(context).textTheme;
    // LayoutBuilder reruns when the keyboard resizes the body, so [typing] stays current.
    return LayoutBuilder(
      builder: (context, _) {
        // While typing, drop the headline so the input always fits above the
        // keyboard. Read the keyboard from the view: Scaffold hides it from the body's MediaQuery.
        final typing = View.of(context).viewInsets.bottom > 0;
        return SafeArea(
          // The floating nav sits behind the keyboard while typing, so don't keep room for it then.
          bottom: !typing,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
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
                      Text(
                        'What are you craving?',
                        textAlign: TextAlign.center,
                        style: text.displaySmall?.copyWith(height: 1.05),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Say it your way. One open spot, right now.',
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    const Spacer(),
                    _LocationProblemBanner(session: session, onFix: () => _askForPlace(session)),
                    // Example cravings only before typing starts: they are a hint, not a menu.
                    ListenableBuilder(
                      listenable: _promptController,
                      builder: (context, _) => _promptController.text.isNotEmpty || typing
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _QuickPicks(
                                onPick: (craving) {
                                  _promptController.text = craving;
                                  _startSearch(craving);
                                },
                              ),
                            ),
                    ),
                    _PromptInput(
                      controller: _promptController,
                      isBusy: false,
                      onSend: () => _startSearch(_promptController.text.trim()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    return PopScope(canPop: false, child: const Center(child: _LoadingView()));
  }

  Widget _buildResult(BuildContext context, AppSession session) {
    final search = session.search;
    return _PickView(
      restaurant: search.current!,
      photo: search.currentPhoto,
      session: session,
      onNo: search.next,
      onYes: _onYes,
      onNewCraving: search.reset,
      onRefine: _onReprompt,
      narrowDown: search.offerRefine && _narrowHiddenFor != search.searchId
          ? _NarrowDown(
              controller: _repromptController,
              onSubmit: _onReprompt,
              onHide: () => setState(() => _narrowHiddenFor = search.searchId),
            )
          : null,
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
    // A refine draft belongs to the search it was typed for.
    _repromptController.clear();
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

/// The pick, full screen: the photo as a hero, then the facts, refine chips
/// and big No / Yes buttons in thumb reach. Every fact shown comes from
/// Places; the reasons are built by the server from Places facts.
class _PickView extends StatelessWidget {
  final Restaurant restaurant;
  final Uint8List? photo;
  final AppSession session;
  final VoidCallback onNo;
  final VoidCallback onYes;
  final VoidCallback onNewCraving;
  final ValueChanged<String> onRefine;

  /// "Narrow it down" (after several Nos), or null.
  final Widget? narrowDown;

  const _PickView({
    required this.restaurant,
    required this.photo,
    required this.session,
    required this.onNo,
    required this.onYes,
    required this.onNewCraving,
    required this.onRefine,
    required this.narrowDown,
  });

  /// One-tap refines: label, and the words sent to the server with the
  /// current intent (TASK-002), so each one changes the search.
  static const refines = [('Cheaper', 'cheaper'), ('Closer', 'closer'), ('Something else', 'something different')];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final saved = session.isBookmarked(restaurant.placeId);
    final facts = [
      if (restaurant.rating != null) '★ ${restaurant.rating!.toStringAsFixed(1)}',
      if ((restaurant.cuisine ?? '').trim().isNotEmpty) restaurant.cuisine!.trim(),
      ?priceLabel(restaurant.priceLevel),
      if (restaurant.distanceMeters != null) '${(restaurant.distanceMeters! / 1000).toStringAsFixed(1)} km',
    ];
    final hasAddress = (restaurant.address ?? '').trim().isNotEmpty;

    return LayoutBuilder(
      builder: (context, box) {
        final photoHeight = (box.maxHeight * 0.42).clamp(160.0, 420.0);
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: photoHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _PhotoHeader(photo: photo),
                          // Google requires the photo author's credit with the photo.
                          if (photo != null && restaurant.photoAuthor != null)
                            Positioned(
                              left: 12,
                              bottom: 12,
                              right: 70,
                              child: _PhotoCredit(author: restaurant.photoAuthor!, uri: restaurant.photoAuthorUri),
                            ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: TextButton.icon(
                              onPressed: onNewCraving,
                              icon: const Icon(Icons.arrow_back_rounded, size: 20),
                              label: const Text('New craving'),
                              style: TextButton.styleFrom(
                                backgroundColor: AppColors.scrim,
                                foregroundColor: AppColors.textPrimary,
                                minimumSize: const Size(48, 44),
                              ),
                            ),
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
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            restaurant.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.headlineMedium,
                          ),
                          // Why this pick: reasons the server built from Places facts.
                          if (restaurant.reasons.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              restaurant.reasons.join(' · '),
                              style: text.bodyLarge?.copyWith(color: AppColors.tomato, fontWeight: FontWeight.w600),
                            ),
                          ],
                          if (facts.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(facts.join(' · '), style: text.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                          ],
                          if (hasAddress) ...[
                            const SizedBox(height: 10),
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
                                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),
                          // Places data shown outside a Google map needs this credit.
                          Text('Google Maps', style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Refine chips and No / Yes stay on screen and in thumb reach,
            // above the home indicator, whatever the screen height or text size.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (label, words) in refines) ...[
                            ActionChip(label: Text(label), onPressed: () => onRefine(words)),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    ?narrowDown,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton(onPressed: onNo, child: const Text('No')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 56,
                            child: FilledButton(onPressed: onYes, child: const Text('Yes')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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
// Narrow it down — a small option under the card after several Nos
// ---------------------------------------------------------------------------

/// A small "Narrow it down" chip that opens a one-line input when tapped.
/// ✕ hides it (closed: for this search; open: back to the chip).
class _NarrowDown extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onHide;
  const _NarrowDown({required this.controller, required this.onSubmit, required this.onHide});

  @override
  State<_NarrowDown> createState() => _NarrowDownState();
}

class _NarrowDownState extends State<_NarrowDown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _open = true),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Narrow it down'),
          ),
          IconButton(
            tooltip: 'Hide',
            iconSize: 18,
            color: AppColors.textMuted,
            onPressed: widget.onHide,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'e.g. cheaper, no seafood',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onSubmitted: widget.onSubmit,
          ),
        ),
        IconButton(
          tooltip: 'Search again',
          color: AppColors.accent,
          onPressed: () => widget.onSubmit(widget.controller.text),
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
        IconButton(
          tooltip: 'Close',
          color: AppColors.textMuted,
          onPressed: () => setState(() => _open = false),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reprompt banner — on the out-of-results screen
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
// Prompt input bar: one rounded composer with mic and send
// ---------------------------------------------------------------------------

class _PromptInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onSend;
  const _PromptInput({required this.controller, required this.isBusy, required this.onSend});

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
      // The opaque cream scrim keeps the icon readable over any photo (3:1+ for controls).
      style: IconButton.styleFrom(backgroundColor: AppColors.scrim, foregroundColor: color),
      icon: Icon(icon),
    );
  }
}
