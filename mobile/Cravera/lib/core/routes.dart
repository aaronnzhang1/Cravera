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
        // Guests may open sign-up (to create an account) without losing their
        // session; anyone already in the app skips the sign-in screen.
        final guestToSignUp = session.isGuest && state.uri.path == signUp;
        if (signedIn && goingToAuth && !guestToSignUp) return appHome;
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
              builder: (context, state) => const HomeScreen(),
            ),
            GoRoute(
              path: appBookmarks,
              builder: (context, state) => const BookmarksScreen(),
            ),
            GoRoute(
              path: appProfile,
              builder: (context, state) => const ProfileScreen(),
            ),
            GoRoute(
              path: appFriends,
              builder: (context, state) => const FriendsScreen(),
            ),
            GoRoute(
              path: appRecs,
              builder: (context, state) => const RecsInboxScreen(),
            ),
            GoRoute(
              path: appNavigate,
              builder: (context, state) => const NavigateScreen(),
            ),
          ],
        ),
      ],
    );
  }
}
