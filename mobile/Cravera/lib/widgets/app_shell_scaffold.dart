import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/routes.dart';
import '../core/session.dart';
import '../services/craving_search.dart';
import 'cravera_background.dart';
import 'glass_nav.dart';

class AppShellScaffold extends StatelessWidget {
  final Widget child;
  const AppShellScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _tabIndexFor(location);
    final search = AppSessionScope.of(context).search;

    // Rebuilt on search changes: while a pick is showing there is no nav bar
    // at all (not just an empty one), so the pick gets the bottom safe area
    // and the bar can't cover the pick or its Yes sheet.
    return ListenableBuilder(
      listenable: search,
      builder: (context, _) => CraveraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: SafeArea(bottom: false, child: child),
          bottomNavigationBar: search.status == SearchStatus.showing && index == 0
              ? null
              : GlassNav(
                  currentIndex: index,
                  onTap: (i) {
                    if (i == 0) context.go(AppRoutes.appHome);
                    if (i == 1) context.go(AppRoutes.appBookmarks);
                    if (i == 2) context.go(AppRoutes.appFriends);
                    if (i == 3) context.go(AppRoutes.appProfile);
                  },
                ),
        ),
      ),
    );
  }
}

int _tabIndexFor(String path) {
  if (path.startsWith(AppRoutes.appBookmarks)) return 1;
  if (path.startsWith(AppRoutes.appFriends)) return 2;
  if (path.startsWith(AppRoutes.appProfile)) return 3;
  return 0;
}
