import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

/// A reading status the user sets on a series themselves — overriding the
/// status the library otherwise infers from reading progress.
enum SeriesStatus {
  /// No manual status; the library infers from progress.
  none('None'),

  /// Actively reading.
  reading('Reading'),

  /// Read everything available; waiting on new chapters.
  caughtUp('Caught up'),

  /// Given up on it.
  dropped('Dropped');

  const SeriesStatus(this.label);

  final String label;

  static SeriesStatus fromName(String? name) {
    for (final s in SeriesStatus.values) {
      if (s.name == name) return s;
    }
    return SeriesStatus.none;
  }
}

/// Persists the user's manual per-series reading status as a single JSON map
/// (`seriesOpdsId` → `status|iso8601`) in SharedPreferences, and syncs it
/// across devices.
///
/// Each entry carries the time it was set so two devices can resolve a
/// conflict by recency rather than by whichever synced last. Clearing a
/// status stores an explicit [SeriesStatus.none] tombstone instead of
/// dropping the key — otherwise the other device's stale "caught up" would
/// simply win the next merge and the clear would undo itself.
class SeriesStatusStore {
  static const _key = 'series_status';

  Future<Map<int, SeriesStatus>> load() async {
    final raw = await _loadRaw();
    return {
      for (final e in raw.entries)
        if (e.value.status != SeriesStatus.none) e.key: e.value.status,
    };
  }

  Future<SeriesStatus> statusFor(int seriesId) async {
    final all = await load();
    return all[seriesId] ?? SeriesStatus.none;
  }

  /// Sets [seriesId]'s status. [SeriesStatus.none] clears it (as a tombstone).
  Future<void> setStatus(int seriesId, SeriesStatus status) async {
    final all = Map<int, _Entry>.of(await _loadRaw());
    all[seriesId] = _Entry(status, DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(all));
    CloudSyncService().pushSeriesStatus();
  }

  Future<Map<int, _Entry>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key));
  }

  Map<int, _Entry> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <int, _Entry>{};
      decoded.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id == null) return;
        final entry = _Entry.parse(v?.toString());
        if (entry != null) result[id] = entry;
      });
      return result;
    } on FormatException {
      return {};
    }
  }

  String _encode(Map<int, _Entry> all) => jsonEncode(<String, String>{
    for (final e in all.entries) '${e.key}': e.value.encoded,
  });

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  Future<String> exportSyncBlob() async => _encode(await _loadRaw());

  /// Merges a cloud blob into local, per series last-writer-wins by the time
  /// the status was set. Returns true if anything changed. Writes directly so
  /// the merge doesn't recurse through [setStatus]'s push hook.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final cloud = _parse(blob);
    if (cloud.isEmpty) return false;
    final merged = Map<int, _Entry>.of(await _loadRaw());
    var changed = false;
    cloud.forEach((id, remote) {
      final local = merged[id];
      if (local != null && !remote.at.isAfter(local.at)) return;
      if (local != null &&
          local.status == remote.status &&
          local.at == remote.at) {
        return;
      }
      merged[id] = remote;
      changed = true;
    });
    if (!changed) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(merged));
    return true;
  }
}

/// A status plus when it was set.
class _Entry {
  const _Entry(this.status, this.at);

  final SeriesStatus status;
  final DateTime at;

  String get encoded => '${status.name}|${at.toIso8601String()}';

  /// Parses `status|iso8601`, tolerating the legacy bare `status` form (which
  /// gets epoch time, so any timestamped edit from either device wins).
  static _Entry? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final sep = raw.indexOf('|');
    if (sep < 0) {
      final legacy = SeriesStatus.fromName(raw);
      if (legacy == SeriesStatus.none) return null;
      return _Entry(legacy, DateTime.fromMillisecondsSinceEpoch(0));
    }
    return _Entry(
      SeriesStatus.fromName(raw.substring(0, sep)),
      DateTime.tryParse(raw.substring(sep + 1)) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
