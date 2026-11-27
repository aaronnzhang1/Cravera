import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cravera/core/session.dart';
import 'package:cravera/main.dart';

void main() {
  testWidgets('Cravera starts on sign in and can enter the app', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(session: AppSession()));
    await tester.pump();

    expect(find.text('Cravera'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'taylor@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('What are you craving?'), findsOneWidget, reason: 'signed in, on Home');
  });

  testWidgets('Continue as guest opens home without an account', (WidgetTester tester) async {
    final session = AppSession();
    await tester.pumpWidget(MyApp(session: session));
    await tester.pump();

    await tester.tap(find.text('Continue as guest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('What are you craving?'), findsOneWidget);
    expect(session.isGuest, isTrue);
    expect(session.isSignedIn, isFalse);

    session.signOut();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(session.canEnterApp, isFalse);
    expect(find.text('Continue as guest'), findsOneWidget);
  });
}
