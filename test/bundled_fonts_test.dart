// A font family the platform cannot resolve does not throw — it falls back to
// the default sans in silence. That is how the app's serif headings vanished
// on Android: `Georgia` is an iOS system font and nothing said so. Every
// family the app names must be bundled, or have something bundled behind it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/main.dart';
import 'package:umbra_reader/widgets/reader_settings_sheet.dart';

Set<String> _bundledFamilies() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  return {
    for (final m in RegExp(
      r'^\s*-\s*family:\s*(.+)$',
      multiLine: true,
    ).allMatches(pubspec))
      m.group(1)!.trim(),
  };
}

void main() {
  test('the pubspec parse finds real families', () {
    // Without this the checks below could pass by parsing nothing at all.
    expect(_bundledFamilies(), containsAll(['Literata', 'Lora']));
  });

  test('every font the reader offers is bundled', () {
    final bundled = _bundledFamilies();
    for (final family in kReaderFonts) {
      if (family.isEmpty) continue; // the deliberate "system font" choice
      expect(
        bundled,
        contains(family),
        reason: '$family is offered in the reader but ships with nothing',
      );
    }
  });

  testWidgets('heading styles keep a bundled serif behind the iOS one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const UmbraReaderApp());

    final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    final bundled = _bundledFamilies();
    final styles = <String, TextStyle?>{
      'titleLarge': theme.textTheme.titleLarge,
      'headlineMedium': theme.textTheme.headlineMedium,
      'appBar title': theme.appBarTheme.titleTextStyle,
    };

    for (final entry in styles.entries) {
      final style = entry.value;
      expect(style, isNotNull, reason: '${entry.key} has no style at all');
      expect(
        style!.fontFamily,
        isNotNull,
        reason: '${entry.key} should be asking for the heading serif',
      );
      final fallbacks = style.fontFamilyFallback ?? const <String>[];
      expect(
        fallbacks.any(bundled.contains),
        isTrue,
        reason:
            '${entry.key} asks for ${style.fontFamily} and falls back to '
            '$fallbacks — none of which ships in the app, so any platform '
            'without ${style.fontFamily} silently loses the serif',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
