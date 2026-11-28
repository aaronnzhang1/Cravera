import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../core/session.dart';
import '../services/saved_hub.dart';
import '../services/saved_places_service.dart';
import '../widgets/glass.dart';

/// Saved (TASK-004): the signed-in person's places, in Want to go and Been,
/// grouped by city. Each place's name and address are fetched fresh when this
/// screen opens (Google's terms don't allow storing them).
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  SavedStatus _tab = SavedStatus.wantToGo;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once per visit: fresh names and addresses for the saved places.
    if (_asked) return;
    final hub = AppSessionScope.of(context).saved;
    if (hub.status == SavedLoadStatus.loaded) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => hub.loadBasics());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);
    final hub = session.saved;
    final text = Theme.of(context).textTheme;
    // The list may finish loading after this screen opened.
    if (!_asked && hub.status == SavedLoadStatus.loaded && hub.items.isNotEmpty) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => hub.loadBasics());
    }
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;

    if (!session.isSignedIn) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
        children: [
          const PageHeader(title: 'Saved', subtitle: 'Places you want to try and places you loved.'),
          _Prompt(
            icon: Icons.bookmark_add_outlined,
            title: 'Create an account to save places',
            body: 'Saved places stay with your account on any phone.',
            action: FilledButton(onPressed: () => context.go(AppRoutes.signUp), child: const Text('Create account')),
          ),
        ],
      );
    }

    final places = hub.byStatus(_tab);
    final groups = <String, List<SavedPlace>>{};
    for (final p in places) {
      final b = hub.basics(p.placeId);
      groups.putIfAbsent(b?.city ?? (b == null && hub.basicsStatus == SavedLoadStatus.loading ? 'Loading…' : 'Other places'), () => []).add(p);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
      children: [
        PageHeader(
          title: 'Saved',
          subtitle: hub.items.isEmpty ? 'Places you save show up here.' : '${hub.items.length} ${hub.items.length == 1 ? 'place' : 'places'}',
        ),
        SegmentedButton<SavedStatus>(
          segments: [
            ButtonSegment(value: SavedStatus.wantToGo, label: Text('Want to go (${hub.byStatus(SavedStatus.wantToGo).length})')),
            ButtonSegment(value: SavedStatus.been, label: Text('Been (${hub.byStatus(SavedStatus.been).length})')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 16),
        if (hub.status == SavedLoadStatus.loading && hub.items.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (hub.status == SavedLoadStatus.failed && hub.items.isEmpty)
          _Prompt(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't load your saved places",
            body: 'Check your connection and try again.',
            action: OutlinedButton(onPressed: hub.load, child: const Text('Try again')),
          )
        else if (places.isEmpty)
          _Prompt(
            icon: _tab == SavedStatus.wantToGo ? Icons.bookmark_add_outlined : Icons.check_circle_outline_rounded,
            title: _tab == SavedStatus.wantToGo ? 'Nothing saved yet' : 'No places marked as been',
            body: _tab == SavedStatus.wantToGo
                ? 'Tap the bookmark on a pick you like.'
                : 'Open a saved place and mark it as Been after you go.',
          )
        else ...[
          if (hub.basicsStatus == SavedLoadStatus.failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text("Couldn't load place names.", style: text.bodyMedium?.copyWith(color: AppColors.textSecondary))),
                  TextButton(onPressed: hub.loadBasics, child: const Text('Try again')),
                ],
              ),
            ),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(entry.key, style: text.titleMedium),
            ),
            for (final p in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SavedRow(place: p, basics: hub.basics(p.placeId), onTap: () => _openPlace(context, p)),
              ),
          ],
          // Places data outside a Google map needs Google's credit.
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4),
            child: Semantics(
              label: 'Google Maps',
              image: true,
              excludeSemantics: true,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset('assets/images/google_maps_logo.png', height: 16, fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openPlace(BuildContext context, SavedPlace place) {
    final hub = AppSessionScope.of(context).saved;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (context) => ListenableBuilder(
        listenable: hub,
        builder: (context, _) {
          // The place may have been removed (or the account changed) meanwhile.
          final current = hub.items.where((p) => p.placeId == place.placeId).firstOrNull;
          if (current == null) return const SizedBox(height: 120, child: Center(child: Text('This place is no longer saved.')));
          return _SavedSheet(place: current, basics: hub.basics(current.placeId), hub: hub);
        },
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const _Prompt({required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Glass(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accentSoft),
            child: Icon(icon, color: AppColors.accent, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  final SavedPlace place;
  final SavedBasics? basics;
  final VoidCallback onTap;
  const _SavedRow({required this.place, required this.basics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = basics;
    final hub = AppSessionScope.of(context).saved;
    final title = b == null
        ? (hub.basicsStatus == SavedLoadStatus.loading || hub.basicsStatus == SavedLoadStatus.idle
            ? 'Loading…'
            : 'Name not loaded: Saved shows names for your newest ${SavedHub.maxPlaces} places')
        : b.missing
            ? 'No longer on Google Maps'
            : b.name ?? "Couldn't load this place";
    return Glass(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(place.status == SavedStatus.been ? Icons.check_circle_rounded : Icons.bookmark_rounded,
                  color: place.status == SavedStatus.been ? AppColors.sage : AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (b?.address != null)
                      Text(b!.address!, style: text.bodySmall?.copyWith(color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (place.note != null) ...[
                      const SizedBox(height: 4),
                      Text(place.note!, style: text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A saved place: move it between Want to go and Been, edit its note, open it
/// in Google Maps, or remove it. Every change is confirmed by the server
/// before it shows; a failure says so and keeps the old state.
class _SavedSheet extends StatefulWidget {
  final SavedPlace place;
  final SavedBasics? basics;
  final SavedHub hub;
  const _SavedSheet({required this.place, required this.basics, required this.hub});

  @override
  State<_SavedSheet> createState() => _SavedSheetState();
}

class _SavedSheetState extends State<_SavedSheet> {
  late final TextEditingController _note = TextEditingController(text: widget.place.note ?? '');
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<SavedOutcome> Function() call, {bool closeOnOk = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await call();
    if (!mounted) return;
    if (outcome == SavedOutcome.ok && closeOnOk) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _message = outcome == SavedOutcome.ok ? 'Saved.' : savedMessage(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = widget.place;
    final b = widget.basics;
    final maps = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(b?.name ?? 'Google')}&query_place_id=${p.placeId}');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(b?.name ?? 'Saved place', style: text.headlineSmall),
            if (b?.address != null) Text(b!.address!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            SegmentedButton<SavedStatus>(
              segments: const [
                ButtonSegment(value: SavedStatus.wantToGo, label: Text('Want to go')),
                ButtonSegment(value: SavedStatus.been, label: Text('Been')),
              ],
              selected: {p.status},
              onSelectionChanged: _busy ? null : (s) => _run(() => widget.hub.setStatus(p.placeId, s.first)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: SavedPlace.maxNoteLength,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Your note', hintText: 'What to order, who to bring…'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => _run(() => widget.hub.setNote(p.placeId, _note.text)),
                child: const Text('Save note'),
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(liveRegion: true, child: Text(_message!, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary))),
              ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(maps, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open in Google Maps'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : () => _run(() => widget.hub.remove(p.placeId), closeOnOk: true),
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              label: const Text('Remove from Saved', style: TextStyle(color: AppColors.danger)),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
      ),
    );
  }
}
