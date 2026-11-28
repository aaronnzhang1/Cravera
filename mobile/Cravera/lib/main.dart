import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/constants.dart';
import 'core/routes.dart';
import 'core/session.dart';
import 'services/auth_service.dart';
import 'services/craving_search.dart';
import 'services/places_service.dart';
import 'services/profile_service.dart';
import 'services/saved_hub.dart';
import 'services/saved_places_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // `.env` is treated as an asset; if a developer runs without it, we still want UI to boot.
  }
  final auth = await _startAuth();
  final places = PlacesService.fromEnv();
  runApp(MyApp(
    session: AppSession(
      search: CravingSearch(places: places),
      auth: auth,
      profiles: auth == null ? null : SupabaseProfileService(Supabase.instance.client),
      saved: SavedHub(
        service: auth == null ? null : SupabaseSavedPlacesService(Supabase.instance.client),
        places: places,
        accessToken: auth == null ? null : () => Supabase.instance.client.auth.currentSession?.accessToken,
      ),
    ),
  ));
}

/// Accounts need the project's publishable key (public; never a secret key).
/// Without it, or if Supabase can't start, the app still runs in guest mode.
Future<AuthService?> _startAuth() async {
  String? key;
  try {
    key = dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY')?.trim();
  } catch (_) {
    return null; // `.env` was never loaded.
  }
  if (key == null || key.isEmpty) return null;
  try {
    // Keeps the session on the device, so people stay signed in across restarts.
    await Supabase.initialize(url: AppConstants.supabaseUrl, publishableKey: key);
    return SupabaseAuthService(Supabase.instance.client);
  } catch (_) {
    return null;
  }
}

class MyApp extends StatelessWidget {
  final AppSession session;
  const MyApp({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AppSessionScope(
      session: session,
      child: MaterialApp.router(
        title: 'Cravera',
        theme: AppTheme.light(),
        routerConfig: AppRoutes.router(session: session),
        // Light screens need dark status-bar icons (clock, battery) on every page.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
