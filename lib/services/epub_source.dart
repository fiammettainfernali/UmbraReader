import 'package:archive/archive.dart';

/// Where an EPUB's bytes come from.
///
/// The parser resolves everything — the container, the OPF, the table of
/// contents, every chapter, every image — through a single "give me this
/// path" call. Naming that as an interface is what lets the same parser
/// read a file on disk or a book on the hub without knowing which, and
/// without any change to parsing, rendering or pagination.
///
/// [bytes] is deliberately synchronous. Image bytes are resolved *during*
/// parsing, so a source that fetches over a network has to have what it
/// needs in hand before parsing starts — see [prefetch]. Making the whole
/// parse asynchronous instead would ripple through every block walker for
/// the sake of one case.
abstract class EpubSource {
  /// The bytes at [path], or null when this source has no such entry.
  List<int>? bytes(String path);

  /// Makes [paths] available to [bytes] before a parse begins.
  ///
  /// A local archive already has everything and does nothing here. A
  /// remote source fetches and caches. Missing paths are not an error:
  /// [bytes] answering null is how "not in this book" is reported, and a
  /// prefetch that throws for one absent image would lose the chapter.
  Future<void> prefetch(Iterable<String> paths) async {}

  /// Releases anything held open. Safe to call more than once.
  void dispose() {}
}

/// An EPUB already decoded in memory — the local, downloaded case.
class LocalArchiveSource implements EpubSource {
  LocalArchiveSource(this._archive);

  final Archive _archive;

  @override
  List<int>? bytes(String path) {
    final normalized = path.replaceAll('\\', '/');
    var found = _archive.findFile(normalized);
    if (found == null) {
      // EPUBs in the wild disagree with their own manifests about case,
      // and a chapter that will not load is worse than a slow lookup.
      final lower = normalized.toLowerCase();
      for (final file in _archive.files) {
        if (file.name.toLowerCase() == lower) {
          found = file;
          break;
        }
      }
    }
    if (found == null || !found.isFile) return null;
    return found.content;
  }

  @override
  Future<void> prefetch(Iterable<String> paths) async {}

  @override
  void dispose() {}
}
