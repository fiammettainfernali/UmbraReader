import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/utils/volume_ordering.dart';

Volume _vol(String title, {String? file, DateTime? updated}) => Volume(
  seriesOpdsId: 1,
  title: title,
  fileName: file ?? '$title.epub',
  downloadUrl: 'https://example/$title',
  fileSizeBytes: 0,
  updatedAt: updated,
);

void main() {
  group('volumeNumber', () {
    test('reads the trailing volume number from the title', () {
      expect(volumeNumber(_vol('Lord of the Mysteries Volume 03')), 3);
      expect(volumeNumber(_vol('Super Insane Doctor Volume 15')), 15);
    });

    test('ignores earlier numbers and keys on the last run of digits', () {
      expect(volumeNumber(_vol('Reborn 2024 - Volume 7')), 7);
    });

    test('falls back to the filename when the title has no number', () {
      expect(volumeNumber(_vol('Some Series', file: 'Some Series Vol 9.epub')),
          9);
    });

    test('returns null when there is no number anywhere', () {
      expect(volumeNumber(_vol('A Standalone Novel', file: 'standalone.epub')),
          isNull);
    });
  });

  group('volumesInReadingOrder', () {
    test('sorts a newest-first feed into ascending volume order', () {
      // OPDS commonly returns newest first; reading order must be ascending.
      final feed = [
        _vol('Series Volume 3'),
        _vol('Series Volume 2'),
        _vol('Series Volume 1'),
      ];
      final ordered = volumesInReadingOrder(feed);
      expect(ordered.map((v) => v.title), [
        'Series Volume 1',
        'Series Volume 2',
        'Series Volume 3',
      ]);
    });

    test('the volume after #2 of 3 is #3, not #1 (the original bug)', () {
      final feed = [
        _vol('Series Volume 3'),
        _vol('Series Volume 2'),
        _vol('Series Volume 1'),
      ];
      final ordered = volumesInReadingOrder(feed);
      final idx = ordered.indexWhere((v) => v.title == 'Series Volume 2');
      expect(ordered[idx + 1].title, 'Series Volume 3');
    });

    test('the latest volume is last, so there is no "next" past it', () {
      final feed = [
        _vol('Series Volume 3'),
        _vol('Series Volume 2'),
        _vol('Series Volume 1'),
      ];
      final ordered = volumesInReadingOrder(feed);
      expect(ordered.last.title, 'Series Volume 3');
      final idx = ordered.indexWhere((v) => v.title == 'Series Volume 3');
      expect(idx, ordered.length - 1); // currentIdx >= length-1 ⇒ no prompt
    });

    test('falls back to updatedAt when titles carry no number', () {
      final feed = [
        _vol('Later', updated: DateTime(2026, 5, 3)),
        _vol('Earlier', updated: DateTime(2026, 5, 1)),
      ];
      final ordered = volumesInReadingOrder(feed);
      expect(ordered.first.title, 'Earlier');
    });

    test('does not mutate the input list', () {
      final feed = [_vol('Series Volume 2'), _vol('Series Volume 1')];
      volumesInReadingOrder(feed);
      expect(feed.first.title, 'Series Volume 2');
    });
  });
}
