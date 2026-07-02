// Smoke test: the app builds and renders the library screen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:umbra_reader/main.dart';

/// Stubs path_provider so the library cache can resolve a directory under
/// `flutter test`, where no real platform is available.
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

/// Pumps frames until the root gate's async settings lookup resolves. The
/// lookup spans several event-loop hops (SharedPreferences plus the Keychain
/// read, which surfaces as an async MissingPluginException under `flutter
/// test` before falling back), so a fixed pump count is brittle.
Future<void> _pumpRootGate(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    // runAsync gives the secure-storage channel call real event-loop time —
    // inside the fake-async test zone its future would never complete.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

void main() {
  testWidgets('App builds and shows the Library screen', (
    WidgetTester tester,
  ) async {
    // onboarding_done = true so the gate falls through to the library
    // immediately instead of stopping at the first-launch welcome screen.
    SharedPreferences.setMockInitialValues(
      <String, Object>{'onboarding_done': true},
    );
    PathProviderPlatform.instance = _FakePathProvider();

    await tester.pumpWidget(const UmbraReaderApp());
    await _pumpRootGate(tester);

    // The library app bar renders on the first frame, before the async
    // library load completes. pumpAndSettle is deliberately not used — the
    // loading spinner animates indefinitely and would never "settle".
    // SliverAppBar.large keeps a collapsed and an expanded title, so
    // 'Library' legitimately appears more than once.
    expect(find.text('Library'), findsWidgets);
  });

  testWidgets('A fresh install lands on the onboarding welcome screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PathProviderPlatform.instance = _FakePathProvider();

    await tester.pumpWidget(const UmbraReaderApp());
    await _pumpRootGate(tester);

    expect(find.text('Welcome to Umbra Reader'), findsOneWidget);
  });
}
