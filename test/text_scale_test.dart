// Dynamic Type audit: the app chrome must survive large accessibility text
// sizes without RenderFlex overflows (which throw under flutter test).
//
// The reader page itself deliberately ignores system text scale — font size
// is a first-class reader setting — but everything around it (library,
// onboarding, settings) must scale.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/main.dart';

import 'helpers/test_db.dart';

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

/// Pumps [child] wrapped in a MediaQuery forcing accessibility text scale.
Future<void> _pumpScaled(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: child,
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

void main() {
  setUp(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    await useInMemoryDatabase();
  });

  testWidgets('onboarding survives 2.0x text scale', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pumpScaled(tester, const UmbraReaderApp());
    expect(find.text('Welcome to Umbra Reader'), findsOneWidget);
    // Overflows would have thrown by now; also make sure the CTA is there.
    expect(tester.takeException(), isNull);
  });

  testWidgets('library (empty, no server) survives 2.0x text scale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_done': true,
    });
    await _pumpScaled(tester, const UmbraReaderApp());
    expect(find.text('Library'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
