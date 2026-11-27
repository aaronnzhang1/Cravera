import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/sign_in_screen.dart';
import '../screens/sign_up_screen.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/home_screen.dart';
import '../screens/navigate_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/recs_inbox_screen.dart';
import 'session.dart';
import '../widgets/app_shell_scaffold.dart';

class AppRoutes {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';

  static const appHome = '/app/home';
  static const appBookmarks = '/app/bookmarks';
  static const appProfile = '/app/profile';

  static const appFriends = '/app/friends';
  static const appRecs = '/app/recs';
  static const appNavigate = '/app/navigate';

  static GoRouter router({required AppSession session}) {
    return GoRouter(
      initialLocation: signIn,
      refreshListenable: session,
      redirect: (context, state) {
        final signedIn = session.canEnterApp;
        final goingToAuth = state.uri.path == signIn || state.uri.path == signUp;
        final goingToApp = state.uri.path.startsWith('/app');

        if (!signedIn && goingToApp) return signIn;
        // Guests may open sign-up or sign-in (to get an account) without losing
        // their session; signed-in users skip both screens.
        if (session.isSignedIn && goingToAuth) return appHome;
        if (state.uri.path == '/') return signedIn ? appHome : signIn;
        return null;
      },
      routes: [
        GoRoute(
          path: signIn,
          builder: (context, state) => const SignInScreen(),
        ),
        GoRoute(
          path: signUp,
          builder: (context, state) => const SignUpScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => AppShellScaffold(child: child),
          routes: [
            GoRoute(
              path: appHome,
              pageBuilder: (context, state) => _tabPage(state, 0, const HomeScreen()),
            ),
            GoRoute(
              path: appBookmarks,
              pageBuilder: (context, state) => _tabPage(state, 1, const BookmarksScreen()),
            ),
            GoRoute(
              path: appProfile,
              pageBuilder: (context, state) => _tabPage(state, 3, const ProfileScreen()),
            ),
            GoRoute(
              path: appFriends,
              pageBuilder: (context, state) => _tabPage(state, 2, const FriendsScreen()),
            ),
            GoRoute(
              path: appRecs,
              pageBuilder: (context, state) => _tabPage(state, 4, const RecsInboxScreen()),
            ),
            GoRoute(
              path: appNavigate,
              pageBuilder: (context, state) => _tabPage(state, 5, const NavigateScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

/// Where each page sits left to right: the nav bar's tabs (Home 0, Saved 1,
/// Friends 2, Profile 3), then pages opened from them. Moving to a higher
/// number brings the new page in from the right; to a lower one, from the left.
int _currentTab = 0;

/// +1 when the last switch went to a tab on the right, -1 to the left.
int _direction = 1;

/// A tab page that slides in from the side you are moving toward, while the
/// old page slides out the other way. Both fade and blur while moving (the
/// maintainer liked the blur; 2026-11-27) and are sharp once they settle.
Page<void> _tabPage(GoRouterState state, int tab, Widget child) {
  if (tab != _currentTab) {
    _direction = tab > _currentTab ? 1 : -1;
    _currentTab = tab;
  }
  // Each page keeps the direction it arrived from, and picks its exit
  // direction once when it starts leaving, so a quick second tap can't make
  // a page that is still moving jump to the other side.
  final enterFrom = _direction;
  int? exitTo;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(animation.value);
          // Incoming pages arrive from the direction of travel; a leaving page
          // (its animation running backwards) exits the opposite way.
          final leaving = animation.status == AnimationStatus.reverse;
          if (leaving) {
            exitTo ??= -_direction;
          } else {
            exitTo = null;
          }
          final dx = (1 - t) * 0.25 * (leaving ? exitTo! : enterFrom);
          final blur = (1 - t) * 8;
          final moved = FractionalTranslation(
            translation: Offset(dx, 0),
            child: Opacity(opacity: t, child: child),
          );
          // The same wrapper every frame (only switched off once settled), so the
          // page underneath is never remounted and keeps typed text and focus.
          return ImageFiltered(
            enabled: blur >= 0.1,
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: moved,
          );
        },
      );
    },
  );
}

