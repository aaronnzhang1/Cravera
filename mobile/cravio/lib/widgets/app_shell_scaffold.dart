import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/routes.dart';
import 'cravio_background.dart';
import 'expanding_bottom_nav.dart';

class AppShellScaffold extends StatelessWidget {
  final Widget child;
  const AppShellScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _tabIndexFor(location);

    return CravioBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(child: child),
        bottomNavigationBar: ExpandingBottomNav(
          currentIndex: index,
          onTap: (i) {
            if (i == 0) context.go(AppRoutes.appHome);
            if (i == 1) context.go(AppRoutes.appBookmarks);
            if (i == 2) context.go(AppRoutes.appProfile);
          },
        ),
      ),
    );
  }
}

int _tabIndexFor(String path) {
  if (path.startsWith(AppRoutes.appBookmarks)) return 1;
  if (path.startsWith(AppRoutes.appProfile)) return 2;
  return 0;
}
