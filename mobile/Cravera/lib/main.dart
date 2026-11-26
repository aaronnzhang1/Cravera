import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/app_theme.dart';
import 'core/routes.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // `.env` is treated as an asset; if a developer runs without it, we still want UI to boot.
  }
  runApp(MyApp(session: AppSession()));
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
        theme: AppTheme.dark(),
        routerConfig: AppRoutes.router(session: session),
      ),
    );
  }
}
