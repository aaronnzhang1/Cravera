import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cravio/core/session.dart';
import 'package:cravio/main.dart';

void main() {
  testWidgets('Cravio starts on sign in and can enter the app', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(session: AppSession()));
    await tester.pump();

    expect(find.text('cravio.'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'taylor@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Hi taylor'), findsOneWidget);
  });
}
