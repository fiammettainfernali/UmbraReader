/// One volume of a series — a single compiled EPUB batch from Novel Grabber.
///
/// When Novel Grabber adds new chapters it re-compiles the latest volume, so
/// [updatedAt] and [fileSizeBytes] are what sync compares to decide whether a
/// previously downloaded volume needs to be fetched again.
class Volume {
  const Volume({
    required this.seriesOpdsId,
    required this.title,
    required this.fileName,
    required this.downloadUrl,
    required this.fileSizeBytes,
    required this.updatedAt,
  });

  /// The OPDS id of the series this volume belongs to.
  final int seriesOpdsId;

  /// Display title — the EPUB's filename stem.
  final String title;

  /// The EPUB filename, e.g. `Lord of the Mysteries - Volume 03.epub`.
  final String fileName;

  /// Absolute URL to download the EPUB.
  final String downloadUrl;

  /// File size in bytes, or 0 if the feed did not report it.
  final int fileSizeBytes;

  /// When this volume's EPUB was last compiled on the server.
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'seriesOpdsId': seriesOpdsId,
    'title': title,
    'fileName': fileName,
    'downloadUrl': downloadUrl,
    'fileSizeBytes': fileSizeBytes,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory Volume.fromJson(Map<String, dynamic> json) => Volume(
    seriesOpdsId: (json['seriesOpdsId'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
    downloadUrl: json['downloadUrl'] as String? ?? '',
    fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}
