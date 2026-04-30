import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
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
    final title = _titleFor(location);

    return CravioBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.appHome);
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: AppColors.textSecondary,
            tooltip: 'Back',
          ),
        ),
        body: child,
        bottomNavigationBar: ExpandingBottomNav(
          currentIndex: index,
          onTap: (i) {
            switch (i) {
              case 0:
                context.go(AppRoutes.appHome);
                break;
              case 1:
                context.go(AppRoutes.appBookmarks);
                break;
              case 2:
                context.go(AppRoutes.appProfile);
                break;
            }
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

String _titleFor(String path) {
  if (path.startsWith(AppRoutes.appBookmarks)) return 'Bookmarks';
  if (path.startsWith(AppRoutes.appProfile)) return 'Profile';
  if (path.startsWith(AppRoutes.appResults)) return 'Results';
  if (path.startsWith(AppRoutes.appFriends)) return 'Friends';
  if (path.startsWith(AppRoutes.appRecs)) return 'Recs inbox';
  if (path.startsWith(AppRoutes.appNavigate)) return 'Navigate';
  return 'Cravio';
}

