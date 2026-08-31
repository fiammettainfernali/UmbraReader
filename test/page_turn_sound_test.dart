// When the page-turn sound is allowed to make a noise.
//
// The player itself needs a platform, so what is pinned here is the rule —
// which is the part with opinions in it, and the part that would otherwise
// only be discoverable by being annoyed by it on a real phone.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/services/page_turn_sound.dart';

void main() {
  group('shouldPlayPageTurnSound', () {
    test('plays for an ordinary turn when switched on', () {
      expect(
        shouldPlayPageTurnSound(enabled: true, speaking: false,
            autoTurn: false, reseating: false),
        isTrue,
      );
    });

    test('silent when the setting is off', () {
      expect(
        shouldPlayPageTurnSound(enabled: false, speaking: false,
            autoTurn: false, reseating: false),
        isFalse,
      );
    });

    test('silent while read-aloud is speaking', () {
      // A paper rustle dropped into the middle of a spoken sentence reads as
      // a glitch, not as atmosphere.
      expect(
        shouldPlayPageTurnSound(enabled: true, speaking: true,
            autoTurn: false, reseating: false),
        isFalse,
      );
    });

    test('silent for hands-free auto-turning', () {
      // Unattended pages turning on a timer would tick like a clock.
      expect(
        shouldPlayPageTurnSound(enabled: true, speaking: false,
            autoTurn: true, reseating: false),
        isFalse,
      );
    });

    test('silent while the pager is only being re-anchored', () {
      // Repagination moves the reader to whichever page now holds the words
      // they were on. It reaches the pager as the same jump a real turn
      // does, and it was audible: tapping the middle of the screen to open
      // the menu changes the height the text is laid into, so the menu
      // rustled like a page every time it appeared.
      expect(
        shouldPlayPageTurnSound(enabled: true, speaking: false,
            autoTurn: false, reseating: true),
        isFalse,
      );
    });
  });

  group('the setting', () {
    test('is off unless asked for', () {
      // A noise on every page turn is not a default worth choosing for
      // someone else.
      expect(ReaderSettings.defaults.pageTurnSound, isFalse);
    });

    test('survives copyWith of an unrelated field', () {
      final on = ReaderSettings.defaults.copyWith(pageTurnSound: true);
      expect(on.copyWith(fontSize: 22).pageTurnSound, isTrue);
    });

    test('migraine mode silences it, like haptics and motion', () {
      // The preset exists for sensory comfort. A paper rustle on every turn
      // belongs with the things it switches off, not with the ones it leaves
      // alone — and because the preset overrides it, leaving the reader
      // restores whatever they had before.
      final on = ReaderSettings.defaults.copyWith(pageTurnSound: true);
      expect(on.migraineAdjusted().pageTurnSound, isFalse);
    });
  });
}
