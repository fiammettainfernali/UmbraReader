// The arithmetic similarity rests on.
//
// None of this loads the model: a unit test should not read 23MB to check
// that an average is an average. What it does cover is every way the maths
// could be quietly wrong — and quietly is the word, because a bad vector
// does not throw, it just recommends the wrong book forever.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/models/series.dart';
import 'package:umbra_reader/services/text_embedder.dart';

Series _series({
  String title = 'Azure Peak',
  List<String> genres = const ['Cultivation', 'Action'],
  String description = 'A sect elder ascends.',
}) => Series(
  opdsId: 1,
  title: title,
  author: 'Anon',
  description: description,
  genres: genres,
  readingStatus: 'ongoing',
  totalChapters: 100,
  downloadedChapters: 0,
  coverUrl: null,
  updatedAt: null,
  directEpubUrl: null,
  volumesFeedUrl: null,
);

Float32List _vec(List<double> values) => Float32List.fromList(values);

void main() {
  group('meanPool', () {
    test('averages the tokens that are really there', () {
      // Two tokens, two dimensions: [1,2] and [3,4] average to [2,3].
      final pooled = meanPool([1, 2, 3, 4], [1, 1], 2);
      expect(pooled, [2, 3]);
    });

    test('padding is not part of the meaning', () {
      // The second token is padding. Averaging it in would drag every short
      // blurb toward the same point and make them all look alike — the
      // failure would be books that are merely terse looking similar.
      final pooled = meanPool([1, 2, 99, 99], [1, 0], 2);
      expect(pooled, [1, 2]);
    });

    test('a fully masked input gives zeros rather than dividing by none', () {
      expect(meanPool([1, 2, 3, 4], [0, 0], 2), [0, 0]);
    });
  });

  group('l2Normalize', () {
    test('makes a vector unit length', () {
      final unit = l2Normalize(_vec([3, 4]));
      expect(unit[0], closeTo(0.6, 1e-6));
      expect(unit[1], closeTo(0.8, 1e-6));
    });

    test('length is what changes, direction is not', () {
      final short = l2Normalize(_vec([1, 1]));
      final long = l2Normalize(_vec([50, 50]));
      expect(short[0], closeTo(long[0], 1e-6));
      expect(short[1], closeTo(long[1], 1e-6));
    });

    test('a zero vector survives instead of producing NaN', () {
      // Division by zero here would poison every comparison it touched, and
      // NaN compares false against everything rather than erroring.
      final zero = l2Normalize(_vec([0, 0]));
      expect(zero.every((v) => v == 0), isTrue);
    });
  });

  group('cosineSimilarity', () {
    test('the same direction is 1', () {
      final a = l2Normalize(_vec([1, 2, 3]));
      expect(cosineSimilarity(a, a), closeTo(1.0, 1e-6));
    });

    test('unrelated is 0 and opposite is -1', () {
      expect(
        cosineSimilarity(l2Normalize(_vec([1, 0])), l2Normalize(_vec([0, 1]))),
        closeTo(0.0, 1e-6),
      );
      expect(
        cosineSimilarity(l2Normalize(_vec([1, 0])), l2Normalize(_vec([-1, 0]))),
        closeTo(-1.0, 1e-6),
      );
    });

    test('a longer blurb does not win on size alone', () {
      // The whole reason vectors are normalized first: without it, a wordy
      // description would outrank a terse one that is actually closer.
      final terse = l2Normalize(_vec([1, 1]));
      final wordy = l2Normalize(_vec([10, 10]));
      expect(cosineSimilarity(terse, wordy), closeTo(1.0, 1e-6));
    });
  });

  group('centroid', () {
    test('a taste is the average of what was read', () {
      final taste = centroid([
        l2Normalize(_vec([1, 0])),
        l2Normalize(_vec([0, 1])),
      ])!;
      expect(taste[0], closeTo(taste[1], 1e-6));
    });

    test('a book read harder counts for more', () {
      final taste = centroid(
        [l2Normalize(_vec([1, 0])), l2Normalize(_vec([0, 1]))],
        weights: [9, 1],
      )!;
      expect(taste[0], greaterThan(taste[1]));
    });

    test('a book bounced off is left out entirely', () {
      // Weight at or below zero drops the vector rather than subtracting it:
      // "not for me" should not drag taste to the opposite of that book.
      final dropped = centroid(
        [l2Normalize(_vec([1, 0])), l2Normalize(_vec([0, 1]))],
        weights: [1, 0],
      )!;
      expect(dropped[0], closeTo(1.0, 1e-6));
      expect(dropped[1], closeTo(0.0, 1e-6));
    });

    test('nothing read yet is null, not a point in space', () {
      expect(centroid([]), isNull);
      expect(centroid([_vec([1, 0])], weights: [0]), isNull);
    });

    test('the result is unit length, so it can be compared directly', () {
      final taste = centroid([_vec([3, 4]), _vec([6, 8])])!;
      expect(cosineSimilarity(taste, taste), closeTo(1.0, 1e-6));
    });
  });

  group('embeddingTextFor', () {
    test('carries title, genres and blurb', () {
      final text = embeddingTextFor(_series());
      expect(text, contains('Azure Peak'));
      expect(text, contains('Cultivation'));
      expect(text, contains('sect elder'));
    });

    test('a book with no blurb still has something to index', () {
      // 118 of 1,016 novels have no usable description. They must still be
      // placed somewhere rather than dropped out of the library.
      final text = embeddingTextFor(_series(description: ''));
      expect(text, contains('Azure Peak'));
      expect(text, contains('Cultivation'));
      expect(text.trim(), isNotEmpty);
    });

    test('genres arrive as words, not as a label soup', () {
      // The library holds 1,213 distinct genre strings. Joined as plain
      // text the model can read them; as opaque labels they were 1,213
      // unrelated tokens, which is most of why similarity was poor.
      final text = embeddingTextFor(
        _series(genres: ['Xianxia', 'Male Lead', '']),
      );
      expect(text, contains('Xianxia, Male Lead'));
      expect(text, isNot(contains(', .')));
    });
  });
}
