import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/series.dart';
import 'settings_service.dart';

/// Raised when the OPDS server can't be reached or returns something
/// unexpected. The [message] is safe to show directly to the user.
class OpdsException implements Exception {
  OpdsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to Novel Grabber's OPDS server: fetches and parses the catalog feeds.
class OpdsClient {
  OpdsClient(this.settings);

  final OpdsSettings settings;

  /// HTTP headers carrying basic auth, if credentials are set. Also used by
  /// the UI when loading cover images (those endpoints need auth too).
  Map<String, String> get authHeaders {
    if (!settings.hasAuth) return const {};
    final token = base64Encode(
      utf8.encode('${settings.username}:${settings.password}'),
    );
    return {'Authorization': 'Basic $token'};
  }

  /// Fetches every series in the library (the OPDS "All Books" feed).
  Future<List<Series>> fetchLibrary() async {
    final uri = Uri.parse('${settings.baseUrl}/opds/all');
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: authHeaders)
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw OpdsException(
        'Could not reach the server at ${settings.baseUrl}.\n\n'
        'Make sure Novel Grabber is running, the OPDS server is started, '
        'and your phone is on the same Wi-Fi network.\n\n($e)',
      );
    }

    if (response.statusCode == 401) {
      throw OpdsException(
        'Authentication failed — check the username and password.',
      );
    }
    if (response.statusCode != 200) {
      throw OpdsException('Server returned HTTP ${response.statusCode}.');
    }

    return _parseLibraryFeed(response.body);
  }

  List<Series> _parseLibraryFeed(String xmlBody) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlBody);
    } on XmlException catch (e) {
      throw OpdsException('The server response was not a valid OPDS feed.\n($e)');
    }

    final series = <Series>[];
    for (final entry in doc.findAllElements('entry')) {
      final parsed = _parseEntry(entry);
      if (parsed != null) series.add(parsed);
    }
    return series;
  }

  Series? _parseEntry(XmlElement entry) {
    final opdsId = _extractNovelId(entry.getElement('id')?.innerText ?? '');
    if (opdsId == null) return null;

    final genres = entry
        .findElements('dc:subject')
        .map((e) => e.innerText.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    var totalChapters = 0;
    var downloadedChapters = 0;
    final chapters = entry.getElement('ng:chapters');
    if (chapters != null) {
      totalChapters = int.tryParse(chapters.getAttribute('total') ?? '') ?? 0;
      downloadedChapters =
          int.tryParse(chapters.getAttribute('downloaded') ?? '') ?? 0;
    }

    String? coverUrl;
    String? directEpubUrl;
    String? volumesFeedUrl;
    for (final link in entry.findElements('link')) {
      final rel = link.getAttribute('rel') ?? '';
      final href = link.getAttribute('href');
      if (href == null || href.isEmpty) continue;
      if (rel == 'http://opds-spec.org/image' ||
          rel == 'http://opds-spec.org/image/thumbnail') {
        coverUrl ??= href;
      } else if (rel == 'http://opds-spec.org/acquisition') {
        directEpubUrl = href;
      } else if (rel == 'subsection') {
        volumesFeedUrl = href;
      }
    }

    return Series(
      opdsId: opdsId,
      title: entry.getElement('title')?.innerText.trim() ?? 'Untitled',
      author:
          entry.getElement('author')?.getElement('name')?.innerText.trim() ??
          'Unknown',
      description: entry.getElement('summary')?.innerText.trim() ?? '',
      genres: genres,
      readingStatus:
          entry.getElement('ng:readingStatus')?.innerText.trim() ?? 'ongoing',
      totalChapters: totalChapters,
      downloadedChapters: downloadedChapters,
      coverUrl: coverUrl,
      updatedAt: DateTime.tryParse(
        entry.getElement('updated')?.innerText.trim() ?? '',
      ),
      directEpubUrl: directEpubUrl,
      volumesFeedUrl: volumesFeedUrl,
    );
  }

  /// Extracts the numeric id from `urn:novel-grabber:novel:<id>`.
  static int? _extractNovelId(String urn) {
    final match = RegExp(r'novel:(\d+)$').firstMatch(urn.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
