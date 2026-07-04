import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/bookmark.dart';
import '../models/volume.dart';
import 'bookmark_store.dart';
import 'library_cache.dart';
import 'library_storage.dart';
import 'reading_progress_store.dart';

/// Renders every highlight and note across the whole library into one
/// Markdown document — the "take my annotations to Obsidian/Notes" export.
/// (The per-book variant lives on the Highlights screen.)
class AnnotationsExport {
  AnnotationsExport({LibraryStorage? storage})
    : _storage = storage ?? LibraryStorage();

  final LibraryStorage _storage;

  /// The full library's annotations as Markdown, grouped book → chapter,
  /// books ordered by title. Empty string when there are no annotations.
  Future<String> markdown() async {
    // Group all bookmarks by volume key.
    final byVolume = <String, List<Bookmark>>{};
    for (final volume in await _annotatedVolumes()) {
      final marks = await BookmarkStore().list(volume);
      if (marks.isEmpty) continue;
      byVolume['${volume.seriesOpdsId}/${volume.fileName}'] = marks;
    }
    if (byVolume.isEmpty) return '';

    final cache = LibraryCache(_storage);
    await cache.load();

    final sections = <(String, List<Bookmark>)>[];
    for (final entry in byVolume.entries) {
      sections.add((await _titleFor(entry.key, cache), entry.value));
    }
    sections.sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));

    final buffer = StringBuffer('# Umbra Reader annotations\n');
    for (final (title, marks) in sections) {
      buffer.writeln('\n## $title\n');
      String? lastChapter;
      // Oldest-first inside a book reads like the book itself.
      final ordered = [...marks]
        ..sort((a, b) {
          final byChapter = a.chapterIndex.compareTo(b.chapterIndex);
          if (byChapter != 0) return byChapter;
          return a.blockIndex.compareTo(b.blockIndex);
        });
      for (final mark in ordered) {
        if (mark.chapterTitle != lastChapter) {
          buffer.writeln('### ${mark.chapterTitle}\n');
          lastChapter = mark.chapterTitle;
        }
        final tag = mark.isHighlight ? 'Highlight' : 'Bookmark';
        buffer.writeln('- **$tag** — ${mark.snippet}');
        if (mark.note.isNotEmpty) {
          buffer.writeln('  > ${mark.note.replaceAll('\n', '\n  > ')}');
        }
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  /// Writes the Markdown to a shareable temp file; null when there is
  /// nothing to export.
  Future<File?> exportToFile() async {
    final text = await markdown();
    if (text.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/umbra-annotations-$stamp.md');
    await file.writeAsString(text);
    return file;
  }

  /// Volumes that have any saved bookmarks: derived from the reading
  /// entries (which carry volume snapshots) plus the bookmark backup keys
  /// for volumes with annotations but no reading progress snapshot.
  Future<List<Volume>> _annotatedVolumes() async {
    final seen = <String>{};
    final out = <Volume>[];
    for (final entry in await ReadingProgressStore().allEntries()) {
      final key = '${entry.volume.seriesOpdsId}/${entry.volume.fileName}';
      if (seen.add(key)) out.add(entry.volume);
    }
    final backupKeys = await BookmarkStore().exportBackupEntries();
    for (final fullKey in backupKeys.keys) {
      final key = fullKey.substring('bookmarks:'.length);
      if (!seen.add(key)) continue;
      final slash = key.indexOf('/');
      if (slash <= 0) continue;
      final seriesId = int.tryParse(key.substring(0, slash));
      if (seriesId == null) continue;
      out.add(
        Volume(
          seriesOpdsId: seriesId,
          title: key.substring(slash + 1),
          fileName: key.substring(slash + 1),
          downloadUrl: '',
          fileSizeBytes: 0,
          updatedAt: null,
        ),
      );
    }
    return out;
  }

  /// Best display title for a volume key: cached volume title, else the
  /// file name.
  Future<String> _titleFor(String key, LibraryCache cache) async {
    final slash = key.indexOf('/');
    final seriesId = int.tryParse(key.substring(0, slash));
    final fileName = key.substring(slash + 1);
    if (seriesId != null) {
      final cached = cache.volumesFor(seriesId);
      final match = cached?.where((v) => v.fileName == fileName).firstOrNull;
      if (match != null) return match.title;
    }
    return fileName;
  }
}
