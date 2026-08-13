import '../models/series.dart';
import 'library_cache.dart';
import 'library_storage.dart';
import 'opds_client.dart';
import 'settings_service.dart';

/// Fetches the library from Novel Grabber and writes it to the shared cache.
///
/// Pulled out because more than one screen needs to be able to say "go and
/// look". It used to live only inside the library screen, so that screen was
/// the only thing in the app capable of learning anything new — every other
/// screen read the cache it wrote, and the app fetched once per launch. An
/// app left open all day showed a library frozen at launch, and no gesture
/// anywhere else could fix it.
///
/// Writing through the cache rather than returning only the list is the
/// point: the result lands where every screen already looks, and the write
/// bumps [libraryCacheRevision] so screens watching it redraw.
class LibraryRefresh {
  const LibraryRefresh();

  /// Returns the fetched series, or null if the server couldn't be reached.
  ///
  /// Null rather than a throw because being offline is an ordinary state
  /// here, not a failure: callers keep showing the cached library, which is
  /// what the cache is for. Callers that need to explain the failure to the
  /// reader — the library screen, which has an offline banner — use the
  /// client directly.
  Future<List<Series>?> run(OpdsSettings settings) async {
    if (!settings.isConfigured) return null;
    final List<Series> library;
    try {
      library = await OpdsClient(settings).fetchLibrary();
    } on OpdsException {
      return null;
    }
    final cache = LibraryCache(LibraryStorage());
    // Load before saving: a fresh instance holds no volumes, and flushing
    // one would write an empty volume map over the real one.
    await cache.load();
    await cache.saveSeries(library);
    return library;
  }
}
