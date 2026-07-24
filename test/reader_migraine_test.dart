// Migraine mode: a comfort preset composed from the existing reader
// primitives, and — critically — fully reversible. Switching it off must give
// the reader back exactly the setup they had, or the mode is a trap.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/models/reader_theme.dart';
import 'package:umbra_reader/services/reader_preferences.dart';

void main() {
  group('migraineAdjusted', () {
    test('applies the comfort preset', () {
      final m = ReaderSettings.defaults.migraineAdjusted();
      expect(m.themeId, 'dark');
      expect(m.overlayTint, 'green');
      expect(m.overlaySeverity, greaterThan(0));
      expect(m.brightness, lessThan(0.5), reason: 'photophobia: dim it');
      expect(m.reduceAnimations, isTrue);
      expect(m.pageAnimations, isFalse, reason: 'motion sensitivity');
      expect(m.hapticFeedback, isFalse);
      expect(m.autoScroll, isFalse);
      expect(m.autoPageSeconds, 0);
    });

    test('never picks the stark pure-black theme', () {
      // Max contrast is itself a trigger; the preset wants charcoal + soft
      // grey, not white-on-black.
      expect(
        ReaderSettings.defaults.migraineAdjusted().themeId,
        isNot('black'),
      );
    });

    test('green off drops the wash but keeps everything else', () {
      final m = ReaderSettings.defaults
          .copyWith(migraineGreen: false)
          .migraineAdjusted();
      expect(m.overlayTint, kOverlayTintNone);
      expect(m.overlaySeverity, 0);
      expect(m.themeId, 'dark', reason: 'the rest of the preset still applies');
      expect(m.reduceAnimations, isTrue);
      expect(m.brightness, lessThan(0.5));
    });

    test('text sizes only ever grow', () {
      // Someone already reading large keeps their size.
      final big = ReaderSettings.defaults
          .copyWith(
            fontSize: 26,
            lineHeight: 2.0,
            paragraphSpacing: 20,
            margin: 40,
          )
          .migraineAdjusted();
      expect(big.fontSize, 26);
      expect(big.lineHeight, 2.0);
      expect(big.paragraphSpacing, 20);
      expect(big.margin, 40);

      final small = ReaderSettings.defaults
          .copyWith(fontSize: 14, lineHeight: 1.2, margin: 10)
          .migraineAdjusted();
      expect(small.fontSize, greaterThanOrEqualTo(20));
      expect(small.lineHeight, greaterThanOrEqualTo(1.75));
      expect(small.margin, greaterThanOrEqualTo(28));
    });
  });

  group('reversibility', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('switching off restores exactly what was overridden', () async {
      final prefs = ReaderPreferences();
      final before = ReaderSettings.defaults.copyWith(
        themeId: 'sepia',
        brightness: 0.9,
        fontSize: 17,
        lineHeight: 1.5,
        margin: 18,
        hapticFeedback: true,
        reduceAnimations: false,
        autoPageSeconds: 30,
      );
      await prefs.saveMigraineSnapshot(before);

      final during = before.migraineAdjusted();
      // Sanity: the preset genuinely changed things.
      expect(during.themeId, 'dark');
      expect(during.fontSize, greaterThan(before.fontSize));
      expect(during.hapticFeedback, isFalse);

      final after = await prefs.restoreMigraineSnapshot(during);
      expect(after.themeId, 'sepia');
      expect(after.brightness, 0.9);
      expect(after.fontSize, 17);
      expect(after.lineHeight, 1.5);
      expect(after.margin, 18);
      expect(after.hapticFeedback, isTrue);
      expect(after.reduceAnimations, isFalse);
      expect(after.autoPageSeconds, 30);
    });

    test('restoring with no snapshot leaves settings untouched', () async {
      // Never strand the reader in the preset.
      final s = ReaderSettings.defaults.copyWith(themeId: 'grey');
      final out = await ReaderPreferences().restoreMigraineSnapshot(s);
      expect(out.themeId, 'grey');
    });

    test('a snapshot is consumed once, not replayed', () async {
      final prefs = ReaderPreferences();
      await prefs.saveMigraineSnapshot(
        ReaderSettings.defaults.copyWith(themeId: 'sepia'),
      );
      final first = await prefs.restoreMigraineSnapshot(
        ReaderSettings.defaults.copyWith(themeId: 'dark'),
      );
      expect(first.themeId, 'sepia');

      final second = await prefs.restoreMigraineSnapshot(
        ReaderSettings.defaults.copyWith(themeId: 'grey'),
      );
      expect(
        second.themeId,
        'grey',
        reason: 'a spent snapshot must not resurrect stale settings',
      );
    });

    test('the flags round-trip through save/load', () async {
      final prefs = ReaderPreferences();
      await prefs.save(
        ReaderSettings.defaults.copyWith(
          migraineMode: true,
          migraineGreen: false,
        ),
      );
      final loaded = await prefs.load();
      expect(loaded.migraineMode, isTrue);
      expect(loaded.migraineGreen, isFalse);
    });
  });
}
