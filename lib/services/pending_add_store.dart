import 'dart:convert';

import '../db/app_database.dart';
import 'control_client.dart';

/// A novel you asked to add while Novel Grabber was out of reach.
class PendingAdd {
  const PendingAdd({
    required this.id,
    required this.url,
    required this.label,
    required this.queuedAt,
    this.force = false,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String url;

  /// What to call it in the list. The page title where the browser knew
  /// one, otherwise the URL — a pending row has never been scraped, so
  /// there is no real title to show yet.
  final String label;

  final DateTime queuedAt;

  /// Carried through so a "yes, add it anyway" made offline is still an
  /// override when it finally reaches the server.
  final bool force;

  final int attempts;
  final String? lastError;

  PendingAdd copyWith({int? attempts, String? lastError, bool? force}) =>
      PendingAdd(
        id: id,
        url: url,
        label: label,
        queuedAt: queuedAt,
        force: force ?? this.force,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'label': label,
    'queuedAt': queuedAt.toIso8601String(),
    'force': force,
    'attempts': attempts,
    'lastError': lastError,
  };

  static PendingAdd? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final url = j['url'] as String?;
    if (id == null || id.isEmpty || url == null || url.isEmpty) return null;
    return PendingAdd(
      id: id,
      url: url,
      label: j['label'] as String? ?? url,
      queuedAt:
          DateTime.tryParse(j['queuedAt'] as String? ?? '') ?? DateTime.now(),
      force: j['force'] == true,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      lastError: j['lastError'] as String?,
    );
  }
}

/// What a flush did, so the UI can say something specific.
class FlushReport {
  const FlushReport({
    this.sent = 0,
    this.alreadyHad = 0,
    this.failed = 0,
    this.stillWaiting = 0,
  });

  final int sent;
  final int alreadyHad;
  final int failed;
  final int stillWaiting;

  bool get didAnything => sent > 0 || alreadyHad > 0 || failed > 0;

  /// A sentence for a snackbar, or null when there is nothing to report.
  String? get summary {
    if (!didAnything) return null;
    final parts = <String>[
      if (sent > 0) '$sent sent to Novel Grabber',
      if (alreadyHad > 0) '$alreadyHad already in your library',
      if (failed > 0) '$failed rejected',
    ];
    final tail = stillWaiting > 0 ? ' · $stillWaiting still waiting' : '';
    return '${parts.join(' · ')}$tail';
  }
}

/// Novels queued for adding while the server was unreachable.
///
/// The phone is often somewhere Novel Grabber is not — away from home, or
/// with the desktop asleep — and finding something worth reading does not
/// wait for that. This keeps the intent locally and replays it the next
/// time the server answers, so browsing is useful offline.
///
/// Local only, deliberately: this is an instruction in flight, not user
/// data. Syncing it would risk two devices sending the same add twice, and
/// the queue empties itself as soon as either one reaches the server.
class PendingAddStore {
  static const _key = 'pending_novel_adds';

  /// A hard ceiling, so a long spell offline can't grow an unbounded list
  /// that then floods the server in one burst.
  static const int maxPending = 100;

  AppDatabase get _db => AppDatabase.instance;

  Future<List<PendingAdd>> list() async => _decode(await _db.kvGet(_key));

  /// Queues [url]. Re-queuing the same URL updates the existing entry
  /// rather than stacking a second copy — tapping add twice while offline
  /// means one intention, not two.
  Future<List<PendingAdd>> enqueue(
    String url, {
    String? label,
    bool force = false,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return list();
    final all = await list();
    final existing = all.indexWhere((p) => p.url == trimmed);
    if (existing >= 0) {
      final next = [...all];
      next[existing] = all[existing].copyWith(
        force: force || all[existing].force,
      );
      return _write(next);
    }
    if (all.length >= maxPending) return all;
    return _write([
      ...all,
      PendingAdd(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        url: trimmed,
        label: (label ?? '').trim().isEmpty ? trimmed : label!.trim(),
        queuedAt: DateTime.now(),
        force: force,
      ),
    ]);
  }

  Future<List<PendingAdd>> remove(String id) async {
    final all = await list();
    return _write([
      for (final p in all)
        if (p.id != id) p,
    ]);
  }

  Future<void> clear() => _db.kvSet(_key, '[]');

  /// Sends everything waiting, oldest first.
  ///
  /// An entry is only kept when the server could not be reached — that is
  /// the one failure retrying can fix. Anything the server answered,
  /// including "you already have this", is a decision, and replaying it
  /// forever would nag about a question already settled.
  Future<FlushReport> flush(ControlClient client) async {
    final all = await list();
    if (all.isEmpty) return const FlushReport();

    var sent = 0;
    var alreadyHad = 0;
    var failed = 0;
    final keep = <PendingAdd>[];

    for (final entry in all) {
      try {
        await client.addNovel(entry.url, force: entry.force);
        sent++;
      } on DuplicateNovelException {
        alreadyHad++;
      } on ControlException catch (e) {
        if (e.isUnreachable) {
          // Still offline. Stop here rather than hammering every entry
          // against a server that plainly isn't there, and keep the rest
          // in their original order.
          keep.add(
            entry.copyWith(attempts: entry.attempts + 1, lastError: e.message),
          );
          keep.addAll(all.skipWhile((p) => p.id != entry.id).skip(1));
          break;
        }
        failed++;
      }
    }

    await _write(keep);
    return FlushReport(
      sent: sent,
      alreadyHad: alreadyHad,
      failed: failed,
      stillWaiting: keep.length,
    );
  }

  Future<List<PendingAdd>> _write(List<PendingAdd> entries) async {
    await _db.kvSet(_key, jsonEncode([for (final e in entries) e.toJson()]));
    return entries;
  }

  static List<PendingAdd> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>) ?PendingAdd.fromJson(e),
      ];
    } on FormatException {
      return const [];
    }
  }
}
