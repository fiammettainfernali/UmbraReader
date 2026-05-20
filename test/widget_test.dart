// Smoke test: the app builds and renders the library screen.

import 'dart:io';

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

void main() {
  testWidgets('App builds and shows the Library screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PathProviderPlatform.instance = _FakePathProvider();

    await tester.pumpWidget(const UmbraReaderApp());
    await tester.pump();

    // The library app bar renders on the first frame, before the async
    // library load completes. pumpAndSettle is deliberately not used — the
    // loading spinner animates indefinitely and would never "settle".
    // SliverAppBar.large keeps a collapsed and an expanded title, so
    // 'Library' legitimately appears more than once.
    expect(find.text('Library'), findsWidgets);
  });
}
