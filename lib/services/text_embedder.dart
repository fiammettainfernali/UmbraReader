// Turning a book into a point in space, so "like this one" can be measured
// instead of guessed at.
//
// What this replaces: every judgement the app makes about what a book IS
// comes from scraper metadata — a genre string and the words in its blurb.
// Across this library that is 1,213 distinct genre labels for 1,016 novels,
// so "Xianxia", "xianxia", "Cultivation" and "Chinese Fantasy" are four
// unrelated tokens, and similarity between two books is however many words
// their descriptions happen to share. That is why an action cultivation
// novel could sit next to age regression: they shared vocabulary.
//
// An embedding model reads the text and returns a vector. Books that are
// about the same kind of thing land near each other whatever words their
// blurbs used, and nothing has to be hand-weighted for it to work. The
// model is all-MiniLM-L6-v2, quantised: 23MB, 384 dimensions, Apache-2.0.
//
// Deliberately split: the maths below the class is pure and tested, and the
// class is the thin part that owns the model. A unit test should not have
// to load 23MB to check that cosine similarity is cosine similarity.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_bert_tokenizer/dart_bert_tokenizer.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../models/series.dart';

/// Vector width of all-MiniLM-L6-v2.
const int kEmbeddingDimensions = 384;

/// What the model was trained to read at once. The bundled tokenizer.json
/// ships `truncation.max_length` of 128, which would quietly discard half
/// of a 736-character blurb — the median in this library — so it is raised
/// on load rather than accepted.
const int kMaxTokens = 256;

const String _modelAsset = 'assets/models/minilm/model_quantized.onnx';
const String _tokenizerAsset = 'assets/models/minilm/tokenizer.json';

/// The text a series is indexed by.
///
/// Title first because it often carries the subgenre outright ("…Cultivation
/// System"), then genres, then the blurb. Genres are kept despite the messy
/// vocabulary: as free text they stop being 1,213 unrelated labels and start
/// being words the model understands.
String embeddingTextFor(Series series) {
  final parts = <String>[
    series.title.trim(),
    if (series.genres.isNotEmpty)
      series.genres.map((g) => g.trim()).where((g) => g.isNotEmpty).join(', '),
    series.description.trim(),
  ].where((p) => p.isNotEmpty);
  return parts.join('. ');
}

/// Collapses the model's per-token output into one vector for the text.
///
/// Mean of the token vectors, counting only real tokens: padding carries no
/// meaning, and averaging it in would drag every short blurb toward the same
/// point and make them all look alike.
Float32List meanPool(List<double> hidden, List<int> attentionMask, int dims) {
  final pooled = Float32List(dims);
  var counted = 0;
  for (var token = 0; token < attentionMask.length; token++) {
    if (attentionMask[token] == 0) continue;
    counted++;
    final offset = token * dims;
    for (var d = 0; d < dims; d++) {
      pooled[d] += hidden[offset + d];
    }
  }
  if (counted == 0) return pooled;
  for (var d = 0; d < dims; d++) {
    pooled[d] /= counted;
  }
  return pooled;
}

/// Scales a vector to unit length, which makes cosine similarity a plain dot
/// product and stops a wordy blurb outranking a terse one on sheer magnitude.
Float32List l2Normalize(Float32List vector) {
  var sum = 0.0;
  for (final v in vector) {
    sum += v * v;
  }
  final length = sqrt(sum);
  if (length == 0) return vector;
  final out = Float32List(vector.length);
  for (var i = 0; i < vector.length; i++) {
    out[i] = vector[i] / length;
  }
  return out;
}

/// −1 to 1, where 1 is "about the same thing". Assumes both are normalized.
double cosineSimilarity(Float32List a, Float32List b) {
  final n = min(a.length, b.length);
  var dot = 0.0;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

/// The average of several vectors, re-normalized — a taste built out of
/// books, or a series built out of its volumes.
///
/// [weights] lets a book count for more than another; passing none treats
/// them equally. A weight of zero or less drops its vector entirely, which
/// is how a book someone bounced off stays out of their taste.
Float32List? centroid(List<Float32List> vectors, {List<double>? weights}) {
  if (vectors.isEmpty) return null;
  final dims = vectors.first.length;
  final sum = Float32List(dims);
  var total = 0.0;
  for (var i = 0; i < vectors.length; i++) {
    final weight = weights == null ? 1.0 : weights[i];
    if (weight <= 0) continue;
    total += weight;
    final v = vectors[i];
    for (var d = 0; d < dims; d++) {
      sum[d] += v[d] * weight;
    }
  }
  if (total == 0) return null;
  for (var d = 0; d < dims; d++) {
    sum[d] /= total;
  }
  return l2Normalize(sum);
}

/// Runs the model. One instance, loaded once, reused.
class TextEmbedder {
  TextEmbedder({this.modelAsset = _modelAsset, this.tokenizerAsset = _tokenizerAsset});

  final String modelAsset;
  final String tokenizerAsset;

  OrtSession? _session;
  WordPieceTokenizer? _tokenizer;

  bool get isLoaded => _session != null && _tokenizer != null;

  /// Loads the model and tokenizer. Safe to call repeatedly; the second call
  /// is free. Not called in a constructor because it reads 23MB off disk and
  /// the caller should decide when that happens.
  Future<void> load() async {
    if (isLoaded) return;
    final raw = await rootBundle.loadString(tokenizerAsset);
    _tokenizer = WordPieceTokenizer.fromTokenizerJsonString(
      _withLongerInput(raw),
    );
    _session = await OnnxRuntime().createSessionFromAsset(modelAsset);
  }

  /// Raises the tokenizer's own truncation limit to what the model can
  /// actually read. Patched in the JSON rather than after encoding, because
  /// by then the tokens are already gone.
  static String _withLongerInput(String tokenizerJson) {
    final decoded = jsonDecode(tokenizerJson);
    if (decoded is! Map<String, dynamic>) return tokenizerJson;
    final truncation = decoded['truncation'];
    if (truncation is Map<String, dynamic>) {
      truncation['max_length'] = kMaxTokens;
    }
    return jsonEncode(decoded);
  }

  /// One vector for [text], unit length. Empty text gives null rather than a
  /// zero vector, which would otherwise sit at a fixed distance from
  /// everything and quietly become a recommendation.
  Future<Float32List?> embed(String text) async {
    if (text.trim().isEmpty) return null;
    await load();

    final encoding = _tokenizer!.encode(text);
    final length = encoding.ids.length;
    if (length == 0) return null;

    // int64, spelled out. The exported graph declares all three inputs as
    // int64, and the plugin infers a tensor type from the Dart type it is
    // handed: a List<int> of token ids all fit in int32, so it built int32
    // tensors and the runtime refused the call at its first argument check
    // — ORT_INVALID_ARGUMENT, every book, every pass. This one line is why
    // the index held zero vectors for a day while every surface quietly
    // fell back to metadata ranking and looked like it was working.
    final ids = Int64List(length);
    final mask = Int64List(length);
    final types = Int64List(length);
    for (var i = 0; i < length; i++) {
      ids[i] = encoding.ids[i];
      mask[i] = encoding.attentionMask[i];
      types[i] = encoding.typeIds[i];
    }

    final outputs = await _session!.run({
      'input_ids': await OrtValue.fromList(ids, [1, length]),
      'attention_mask': await OrtValue.fromList(mask, [1, length]),
      'token_type_ids': await OrtValue.fromList(types, [1, length]),
    });

    final raw = await outputs['last_hidden_state']!.asList();
    final hidden = _flatten(raw);
    if (hidden.length < length * kEmbeddingDimensions) return null;

    return l2Normalize(meanPool(hidden, mask, kEmbeddingDimensions));
  }

  /// Flattens whatever shape the runtime hands back. The output is
  /// [1, tokens, 384]; some backends return it nested and some flat, and
  /// guessing wrong is a silently wrong vector rather than a crash.
  static List<double> _flatten(Object? value) {
    final out = <double>[];
    void walk(Object? node) {
      if (node is num) {
        out.add(node.toDouble());
      } else if (node is Iterable) {
        for (final child in node) {
          walk(child);
        }
      }
    }

    walk(value);
    return out;
  }

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _tokenizer = null;
  }
}
