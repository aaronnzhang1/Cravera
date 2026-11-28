// Friends preview (TASK-UI-3). Fictional data only.
import 'package:cravera/core/session.dart';
import 'package:cravera/main.dart';
import 'package:cravera/screens/friends_screen.dart';
import 'package:cravera/services/craving_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'craving_search_test.dart' show FakePlaces;

void main() {
  testWidgets('Friends is a preview with an invite, not a list of fake people', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MyApp(session: AppSession(search: CravingSearch(places: FakePlaces((_) => [])))));
    await tester.pump();
    await tester.tap(find.text('Continue as guest'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Friends'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Bring your people'), findsOneWidget);
    for (final demo in ['Maya', 'Jordan', 'Sam']) {
      expect(find.text(demo), findsNothing);
    }
    expect(find.textContaining('coming soon'), findsNothing);

    await tester.tap(find.text('Invite a friend'));
    await tester.pump();
    expect(copied, FriendsScreen.inviteText);
    expect(find.textContaining('Invite copied'), findsOneWidget);
  });
}
