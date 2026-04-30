import 'package:go_router/go_router.dart';

import '../screens/home_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/sign_up_screen.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/navigate_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/recs_inbox_screen.dart';
import '../screens/results_screen.dart';

class AppRoutes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const results = '/results';
  static const navigate = '/navigate';
  static const profile = '/profile';
  static const bookmarks = '/bookmarks';
  static const friends = '/friends';
  static const recs = '/recs';

  static GoRouter router() {
    return GoRouter(
      routes: [
        GoRoute(
          path: home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: signIn,
          builder: (context, state) => const SignInScreen(),
        ),
        GoRoute(
          path: signUp,
          builder: (context, state) => const SignUpScreen(),
        ),
        GoRoute(
          path: results,
          builder: (context, state) => const ResultsScreen(),
        ),
        GoRoute(
          path: navigate,
          builder: (context, state) => const NavigateScreen(),
        ),
        GoRoute(
          path: profile,
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: bookmarks,
          builder: (context, state) => const BookmarksScreen(),
        ),
        GoRoute(
          path: friends,
          builder: (context, state) => const FriendsScreen(),
        ),
        GoRoute(
          path: recs,
          builder: (context, state) => const RecsInboxScreen(),
        ),
      ],
    );
  }
}
