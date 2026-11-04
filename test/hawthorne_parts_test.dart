// The parts the three rebuilt tabs share.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/widgets/hawthorne_parts.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: child),
  ),
);

double _fill(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
    .widthFactor!;

void main() {
  testWidgets('a bar grows to its value, and leaves nothing running', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const GrowingBar(fraction: 0.5)));
    expect(_fill(tester), 0);
    await tester.pumpAndSettle();
    expect(_fill(tester), 0.5);
  });

  testWidgets('under Reduce Motion a bar is simply there', (tester) async {
    await tester.pumpWidget(
      _app(const GrowingBar(fraction: 0.5), disableAnimations: true),
    );
    await tester.pump();
    expect(_fill(tester), 0.5);
  });

  testWidgets('a bar never runs past either end', (tester) async {
    await tester.pumpWidget(_app(const GrowingBar(fraction: 3)));
    await tester.pumpAndSettle();
    expect(_fill(tester), 1);
  });

  testWidgets('an empty bar still shows its track across the full width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [GrowingBar(fraction: 0)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GrowingBar)).width, 200);
  });

  testWidgets('a meter shows its label and number', (tester) async {
    await tester.pumpWidget(
      _app(const MeterRow(label: 'Fantasy', value: '558', fraction: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fantasy'), findsOneWidget);
    expect(find.text('558'), findsOneWidget);
  });

  testWidgets('a long figure shrinks to fit its tile rather than overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 110,
          child: StatTile(value: '1,008,238,000', label: 'chapters'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the striped bar with no value fills, for work of unknown length',
    (tester) async {
      await tester.pumpWidget(_app(const StripedBar()));
      expect(
        tester
            .widget<AnimatedFractionallySizedBox>(
              find.byType(AnimatedFractionallySizedBox),
            )
            .widthFactor,
        1,
      );
    },
  );
}
