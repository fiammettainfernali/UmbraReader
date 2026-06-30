import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/tts_skip.dart';

void main() {
  group('redactForSpeech', () {
    test('no skips returns the text unchanged', () {
      const text = 'Hello (aside) world [1].';
      expect(redactForSpeech(text, const {}), text);
    });

    test('redaction is length-preserving (keeps highlight offsets aligned)', () {
      const text = 'See (this) and [that] and {those} at https://x.io now.';
      final out = redactForSpeech(text, {
        TtsSkip.parentheses,
        TtsSkip.brackets,
        TtsSkip.braces,
        TtsSkip.urls,
      });
      expect(out.length, text.length);
    });

    test('parentheses content is blanked but words outside survive', () {
      const text = 'hello (aside) world';
      final out = redactForSpeech(text, {TtsSkip.parentheses});
      expect(out.contains('aside'), isFalse);
      expect(out.trim().split(RegExp(r'\s+')), ['hello', 'world']);
    });

    test('URLs are removed', () {
      const text = 'go to https://example.com/page now';
      final out = redactForSpeech(text, {TtsSkip.urls});
      expect(out.contains('example.com'), isFalse);
      expect(out.contains('go to'), isTrue);
      expect(out.contains('now'), isTrue);
    });

    test('numeric citations like [12] are removed', () {
      const text = 'As shown [12] in the study.';
      final out = redactForSpeech(text, {TtsSkip.citations});
      expect(out.contains('12'), isFalse);
      expect(out.contains('As shown'), isTrue);
    });

    test('author-year citations are removed', () {
      const text = 'Prior work (Smith, 2020) agrees.';
      final out = redactForSpeech(text, {TtsSkip.citations});
      expect(out.contains('Smith'), isFalse);
      expect(out.contains('Prior work'), isTrue);
    });

    test('encode/parse round-trips a set of skips', () {
      final skips = {TtsSkip.urls, TtsSkip.headings, TtsSkip.braces};
      expect(parseTtsSkips(encodeTtsSkips(skips)), skips);
    });

    test('parse tolerates empty and unknown names', () {
      expect(parseTtsSkips(''), const <TtsSkip>{});
      expect(parseTtsSkips('urls,bogus'), {TtsSkip.urls});
    });
  });
}
