// Umbra Pro entitlement + gate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/pro_service.dart';
import 'package:umbra_reader/widgets/pro_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Builds default to unlocked; tests drive the notifier directly to
    // exercise the locked path.
    ProService().isPro.value = kBuiltInPro;
  });

  tearDown(() => ProService().isPro.value = kBuiltInPro);

  test('builds are unlocked by default (launch flips via dart-define)', () {
    expect(kBuiltInPro, isTrue);
    expect(ProService().isPro.value, isTrue);
  });

  test('markPurchased persists and flips the notifier', () async {
    ProService().isPro.value = false;
    await ProService().markPurchased();
    expect(ProService().isPro.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pro_unlocked'), isTrue);
  });

  testWidgets('requirePro passes through when entitled', (tester) async {
    var allowed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              allowed = await requirePro(context, feature: 'Collections');
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
    expect(find.text('Umbra Pro'), findsNothing);
  });

  testWidgets('requirePro shows the upsell when locked', (tester) async {
    ProService().isPro.value = false;
    bool? allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              allowed = await requirePro(
                context,
                feature: 'Search inside every book',
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Umbra Pro'), findsOneWidget);
    // The tapped feature is listed first and emphasised.
    expect(find.text('Search inside every book'), findsOneWidget);
    // Dismiss → still locked.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
  });

  testWidgets('purchasing mid-sheet unlocks the caller', (tester) async {
    ProService().isPro.value = false;
    bool? allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              allowed = await requirePro(context, feature: 'Collections');
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    // Simulate the (future) StoreKit flow completing while the sheet is up.
    await ProService().markPurchased();
    await tester.tapAt(const Offset(10, 10)); // dismiss
    await tester.pumpAndSettle();
    expect(allowed, isTrue, reason: 'requirePro re-checks after the sheet');
  });
}
