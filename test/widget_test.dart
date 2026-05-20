// Smoke test: the app boots to the library screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:umbra_reader/main.dart';

void main() {
  testWidgets('App boots to the Library screen', (WidgetTester tester) async {
    // No saved settings — the app should show the "not connected" state.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const UmbraReaderApp());
    // Let the async settings load settle.
    await tester.pumpAndSettle();

    // SliverAppBar.large keeps both a collapsed and an expanded title in the
    // tree, so 'Library' legitimately appears more than once.
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
