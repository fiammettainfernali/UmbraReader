/// Metadata recorded when a volume's EPUB is downloaded to the device.
///
/// Comparing a record against the live OPDS feed is how Umbra Reader detects
/// a re-compiled volume: when Novel Grabber adds chapters it rebuilds the
/// volume, changing its server-side `updated` time and file size.
class DownloadRecord {
  const DownloadRecord({
    required this.fileName,
    required this.sizeBytes,
    required this.downloadedAt,
    required this.volumeUpdatedAt,
    required this.etag,
  });

  final String fileName;

  /// Size of the downloaded EPUB, in bytes.
  final int sizeBytes;

  /// When the download completed on this device.
  final DateTime downloadedAt;

  /// The volume's server-side `updated` time at download time.
  final DateTime? volumeUpdatedAt;

  /// HTTP ETag of the downloaded EPUB, for future conditional re-sync.
  final String? etag;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'downloadedAt': downloadedAt.toIso8601String(),
    'volumeUpdatedAt': volumeUpdatedAt?.toIso8601String(),
    'etag': etag,
  };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
    fileName: json['fileName'] as String? ?? '',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    downloadedAt:
        DateTime.tryParse(json['downloadedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    volumeUpdatedAt: DateTime.tryParse(json['volumeUpdatedAt'] as String? ?? ''),
    etag: json['etag'] as String?,
  );
}
