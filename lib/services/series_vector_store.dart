// Where the library's embeddings live between launches.
//
// Embedding 1,016 books is about a minute of phone time, and a blurb does
// not change while the app is closed, so the vectors are written down. What
// makes that safe is the text hash: a book is only re-embedded when the
// text that produced its vector actually changed, so a library refresh
// costs nothing and a rewritten description costs exactly one book.

import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Which model produced the stored vectors.
///
/// Two models' vectors are not comparable — the same book lands somewhere
/// different in each space — so a swap has to invalidate the index rather
/// than quietly mix the two and return nonsense similarity.
const String kEmbeddingModelId = 'all-MiniLM-L6-v2-q';

class SeriesVectorStore {
  AppDatabase get _db => AppDatabase.instance;

  /// Every vector for the current model, by series id.
  Future<Map<int, Float32List>> loadAll() async {
    final rows =
        await (_db.select(_db.seriesVectorRows)
              ..where((t) => t.model.equals(kEmbeddingModelId)))
            .get();
    return {for (final row in rows) row.seriesId: _toFloats(row.vector)};
  }

  /// The text hash held for each series, which is how the indexer knows
  /// what still needs doing. Rows from another model are left out, so a
  /// model swap reports everything as needing work.
  Future<Map<int, String>> indexedHashes() async {
    final rows =
        await (_db.select(_db.seriesVectorRows)
              ..where((t) => t.model.equals(kEmbeddingModelId)))
            .get();
    return {for (final row in rows) row.seriesId: row.textHash};
  }

  Future<void> put(
    int seriesId,
    Float32List vector,
    String textHash, {
    DateTime? now,
  }) => _db
      .into(_db.seriesVectorRows)
      .insertOnConflictUpdate(
        SeriesVectorRowsCompanion.insert(
          seriesId: Value(seriesId),
          vector: _toBytes(vector),
          dimensions: vector.length,
          textHash: textHash,
          model: kEmbeddingModelId,
          updatedAt: (now ?? DateTime.now()).toIso8601String(),
        ),
      );

  /// Drops vectors for series that are no longer in the library, and any
  /// left behind by a previous model. Without this the index only ever
  /// grows, and a swapped model leaves its whole space sitting in the file.
  Future<int> prune(Set<int> keepIds) async {
    final rows = await _db.select(_db.seriesVectorRows).get();
    final doomed = [
      for (final row in rows)
        if (row.model != kEmbeddingModelId || !keepIds.contains(row.seriesId))
          row.seriesId,
    ];
    if (doomed.isEmpty) return 0;
    await (_db.delete(
      _db.seriesVectorRows,
    )..where((t) => t.seriesId.isIn(doomed))).go();
    return doomed.length;
  }

  Future<int> count() async {
    final rows =
        await (_db.select(_db.seriesVectorRows)
              ..where((t) => t.model.equals(kEmbeddingModelId)))
            .get();
    return rows.length;
  }

  Future<void> clear() => _db.delete(_db.seriesVectorRows).go();

  /// Little-endian float32, which is what both sides of this agree on
  /// explicitly rather than inheriting from whatever the device happens to
  /// be — a vector written on one byte order and read on another is not an
  /// error, just silently the wrong book.
  static Uint8List _toBytes(Float32List vector) {
    final bytes = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      bytes.setFloat32(i * 4, vector[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static Float32List _toFloats(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getFloat32(i * 4, Endian.little);
    }
    return out;
  }
}

/// A stable 64-bit hash of the indexed text.
///
/// Written out rather than using String.hashCode, which is only promised to
/// be stable within a single run: a seed that changes between launches
/// would make every book look re-indexed on every start, and the whole
/// library would be embedded again each time the app opened.
String textFingerprint(String text) {
  var hash = 0xcbf29ce484222325;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
