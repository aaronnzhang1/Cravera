import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../core/session.dart';
import '../widgets/cravio_background.dart';
import '../widgets/cravio_pulse_logo.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CravioBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                children: [
                  const SizedBox(height: 10),
                  const CravioPulseLogo(size: 92, duration: Duration(milliseconds: 2600)),
                  const SizedBox(height: 16),
                  Text(
                    'cravio',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'your AI food concierge',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Sign in',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final email = _emailController.text.trim();
                        final nameFromEmail = email.contains('@') ? email.split('@').first : email;
                        AppSessionScope.of(context).signIn(displayName: nameFromEmail.isEmpty ? 'there' : nameFromEmail);
                        context.go(AppRoutes.appHome);
                      },
                      child: const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.signUp),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                    child: const Text('Don’t have an account? Sign up'),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: () {
                      AppSessionScope.of(context).continueAsGuest();
                      context.go(AppRoutes.appHome);
                    },
                    child: const Text('Continue as guest'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
