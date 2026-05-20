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

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
