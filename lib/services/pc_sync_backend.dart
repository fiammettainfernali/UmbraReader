import '../db/app_database.dart';
import 'control_client.dart';
import 'settings_service.dart';
import 'sync_backend.dart';

/// Hawthorne Codex on the computer as this phone's cloud: what iCloud is on
/// the iPhone.
///
/// On Android nothing left the phone. Notes, highlights, bookmarks,
/// collections, glossaries, the reading ledger behind stats and the streak:
/// a lost or reset phone lost them. The computer now keeps the latest blob
/// of each, and its own nightly backup carries them to the external drive.
///
/// The computer keeps whatever it was sent last, so the one way to lose data
/// here is a phone sending before it has read: a fresh install's empty
/// bookmarks would replace the backup of the old ones. So nothing is sent
/// until one pull has read every blob without a failure. Until then, and
/// after any send that fails, the backend is behind, and the next
/// [CloudSyncService.catchUp] pulls, merges and sends everything.
///
/// Like every backend this never throws: the phone's stores hold the truth,
/// and a computer out of reach only means the copy there is older.
class PcSyncBackend extends SyncBackend {
  PcSyncBackend({Future<OpdsSettings> Function()? settings})
    : _loadSettings = settings ?? (() => SettingsService().load());

  final Future<OpdsSettings> Function() _loadSettings;

  /// 'yes' once a pull has read everything the computer keeps.
  static const kPulled = 'pc_sync_pulled';

  /// 'no' once everything has reached the computer; 'yes' again after any
  /// send that didn't.
  static const kBehind = 'pc_sync_behind';

  int _readFailures = 0;
  int _writeFailures = 0;
  bool _pushingAll = false;

  AppDatabase get _db => AppDatabase.instance;

  Future<ControlClient?> _client() async {
    final settings = await _loadSettings();
    if (!settings.isConfigured || !settings.hasAuth) return null;
    return ControlClient(settings);
  }

  Future<bool> _hasPulled() async => await _db.kvGet(kPulled) == 'yes';

  Future<void> _fellBehind() => _db.kvSet(kBehind, 'yes');

  @override
  Future<void> beginPull() async => _readFailures = 0;

  @override
  Future<String?> read(String key) async {
    // One failure already spoils this pull; the rest would only wait out
    // their timeouts one after another.
    if (_readFailures > 0) return null;
    try {
      return await (await _client())?.syncRead(key);
    } on Exception {
      _readFailures++;
      return null;
    }
  }

  @override
  Future<bool> endPull() async {
    if (_readFailures > 0 || await _client() == null) return false;
    await _db.kvSet(kPulled, 'yes');
    return await _db.kvGet(kBehind) != 'no';
  }

  @override
  Future<void> write(String key, String value) async {
    // A store that has never been used exports nothing, so a fresh install
    // can't wipe what is kept. Nothing to keep is not a failed send.
    if (value.isEmpty) return;
    try {
      final client = await _client();
      if (client == null) return;
      if (!await _hasPulled()) {
        await _fellBehind();
        return;
      }
      if (_pushingAll && _writeFailures > 0) return;
      await client.syncWrite(key, value);
    } on Exception {
      _writeFailures++;
      await _fellBehind();
    }
  }

  @override
  Future<bool> needsFullPush() async {
    if (await _client() == null) return false;
    return !await _hasPulled() || await _db.kvGet(kBehind) != 'no';
  }

  @override
  Future<void> beginFullPush() async {
    _writeFailures = 0;
    _pushingAll = true;
  }

  @override
  Future<void> endFullPush() async {
    _pushingAll = false;
    if (_writeFailures == 0 && await _hasPulled()) {
      await _db.kvSet(kBehind, 'no');
    }
  }
}
