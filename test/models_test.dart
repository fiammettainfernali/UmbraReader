// Unit tests for the plain-data models and their derived logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/reader_settings.dart';
import 'package:umbra_reader/models/reader_theme.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/models/volume.dart';
import 'package:umbra_reader/services/reading_progress_store.dart';

void main() {
  group('ReaderSettings.copyWith', () {
    const base = ReaderSettings.defaults;

    test('with no arguments preserves every field', () {
      final copy = base.copyWith();
      expect(copy.mode, base.mode);
      expect(copy.themeId, base.themeId);
      expect(copy.fontFamily, base.fontFamily);
      expect(copy.fontSize, base.fontSize);
      expect(copy.lineHeight, base.lineHeight);
      expect(copy.margin, base.margin);
      expect(copy.speechRate, base.speechRate);
      expect(copy.voiceName, base.voiceName);
      expect(copy.voiceLocale, base.voiceLocale);
      expect(copy.boldText, base.boldText);
      expect(copy.italicText, base.italicText);
      expect(copy.brightness, base.brightness);
      expect(copy.letterSpacing, base.letterSpacing);
      expect(copy.wordSpacing, base.wordSpacing);
      expect(copy.paragraphSpacing, base.paragraphSpacing);
      expect(copy.reduceAnimations, base.reduceAnimations);
      expect(copy.hapticFeedback, base.hapticFeedback);
      expect(copy.sessionMinutes, base.sessionMinutes);
    });

    test('carries the spacing controls', () {
      final copy = base.copyWith(
        letterSpacing: 1.5,
        wordSpacing: 3,
        paragraphSpacing: 10,
      );
      expect(copy.letterSpacing, 1.5);
      expect(copy.wordSpacing, 3);
      expect(copy.paragraphSpacing, 10);
      // Untouched neighbours.
      expect(copy.lineHeight, base.lineHeight);
      expect(copy.margin, base.margin);
    });

    test('changes only the named field', () {
      final copy = base.copyWith(boldText: true);
      expect(copy.boldText, isTrue);
      // Everything else is untouched.
      expect(copy.italicText, base.italicText);
      expect(copy.fontSize, base.fontSize);
      expect(copy.brightness, base.brightness);
    });

    test('carries new values through a chain of copies', () {
      final copy = base
          .copyWith(mode: ReadingMode.paged)
          .copyWith(fontSize: 24)
          .copyWith(brightness: 0.5);
      expect(copy.mode, ReadingMode.paged);
      expect(copy.fontSize, 24);
      expect(copy.brightness, 0.5);
    });

    test('resolves the theme preset from themeId', () {
      expect(base.copyWith(themeId: 'sepia').theme.id, 'sepia');
    });
  });

  group('readerThemeById', () {
    test('returns each built-in theme by id', () {
      for (final preset in kReaderThemes) {
        expect(readerThemeById(preset.id).id, preset.id);
      }
    });

    test('includes the grey theme', () {
      expect(kReaderThemes.any((t) => t.id == 'grey'), isTrue);
    });

    test('falls back to dark for an unknown id', () {
      expect(readerThemeById('does-not-exist').id, 'dark');
    });

    test('isLight reflects background luminance', () {
      expect(readerThemeById('light').isLight, isTrue);
      expect(readerThemeById('black').isLight, isFalse);
    });
  });

  group('ReadingProgress', () {
    test('a fresh position is neither started nor finished', () {
      const p = ReadingProgress(chapterIndex: 0, blockIndex: 0);
      expect(p.isStarted, isFalse);
      expect(p.isFinished, isFalse);
      expect(p.fraction, 0);
    });

    test('is started once past the first paragraph or chapter', () {
      expect(
        const ReadingProgress(chapterIndex: 0, blockIndex: 4).isStarted,
        isTrue,
      );
      expect(
        const ReadingProgress(chapterIndex: 2, blockIndex: 0).isStarted,
        isTrue,
      );
    });

    test('is finished only when the end of the last chapter was reached', () {
      // On the last chapter but NOT at its end → not finished (you can stop
      // mid-final-chapter; it must stay on the Continue Reading shelf).
      expect(
        const ReadingProgress(
          chapterIndex: 9,
          blockIndex: 0,
          chapterCount: 10,
        ).isFinished,
        isFalse,
      );
      // Reached the end → finished.
      expect(
        const ReadingProgress(
          chapterIndex: 9,
          blockIndex: 0,
          chapterCount: 10,
          endReached: true,
        ).isFinished,
        isTrue,
      );
      // Mid-book is never finished.
      expect(
        const ReadingProgress(
          chapterIndex: 5,
          blockIndex: 0,
          chapterCount: 10,
        ).isFinished,
        isFalse,
      );
    });

    test('fraction is the chapter position over the chapter span', () {
      expect(
        const ReadingProgress(
          chapterIndex: 5,
          blockIndex: 0,
          chapterCount: 11,
        ).fraction,
        closeTo(0.5, 1e-9),
      );
    });

    test('fraction is 0 when the chapter count is unknown', () {
      expect(
        const ReadingProgress(chapterIndex: 3, blockIndex: 0).fraction,
        0,
      );
    });
  });

  group('JSON round-trips', () {
    test('Volume survives toJson/fromJson', () {
      final volume = Volume(
        seriesOpdsId: 42,
        title: 'Lord of the Mysteries - Volume 03',
        fileName: 'lotm-v03.epub',
        downloadUrl: 'http://host/lotm-v03.epub',
        fileSizeBytes: 123456,
        updatedAt: DateTime.utc(2026, 5, 1, 12),
      );
      final restored = Volume.fromJson(volume.toJson());
      expect(restored.seriesOpdsId, volume.seriesOpdsId);
      expect(restored.title, volume.title);
      expect(restored.fileName, volume.fileName);
      expect(restored.downloadUrl, volume.downloadUrl);
      expect(restored.fileSizeBytes, volume.fileSizeBytes);
      expect(restored.updatedAt, volume.updatedAt);
    });

    test('Series survives toJson/fromJson', () {
      const series = Series(
        opdsId: 7,
        title: 'Test Series',
        author: 'An Author',
        description: 'A description.',
        genres: ['Action', 'Fantasy'],
        readingStatus: 'ongoing',
        totalChapters: 100,
        downloadedChapters: 80,
        coverUrl: 'http://host/cover.jpg',
        updatedAt: null,
        directEpubUrl: null,
        volumesFeedUrl: 'http://host/volumes',
      );
      final restored = Series.fromJson(series.toJson());
      expect(restored.opdsId, series.opdsId);
      expect(restored.title, series.title);
      expect(restored.genres, series.genres);
      expect(restored.totalChapters, series.totalChapters);
      expect(restored.coverUrl, series.coverUrl);
      expect(restored.volumesFeedUrl, series.volumesFeedUrl);
      expect(restored.hasMultipleVolumes, isTrue);
    });
  });
}
