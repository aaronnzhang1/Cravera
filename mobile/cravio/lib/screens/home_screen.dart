import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cravio'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Home / Chat (placeholder)', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            const TextField(decoration: InputDecoration(hintText: 'Craving input (placeholder)')),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.go(AppRoutes.results),
                child: const Text('Go to results (placeholder)'),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.signIn),
                  child: const Text('Sign In'),
                ),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.signUp),
                  child: const Text('Sign Up'),
                ),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.profile),
                  child: const Text('Profile'),
                ),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.bookmarks),
                  child: const Text('Bookmarks'),
                ),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.friends),
                  child: const Text('Friends'),
                ),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.recs),
                  child: const Text('Recs Inbox'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
