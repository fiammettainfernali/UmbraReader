import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connection details for the Novel Grabber OPDS server.
class OpdsSettings {
  const OpdsSettings({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  /// Server root with no trailing slash and no `/opds` suffix —
  /// e.g. `http://192.168.1.42:8765`.
  final String baseUrl;
  final String username;
  final String password;

  /// True once a server address has been entered.
  bool get isConfigured => baseUrl.isNotEmpty;

  /// True when basic-auth credentials should be sent.
  bool get hasAuth => username.isNotEmpty;

  static const empty = OpdsSettings(baseUrl: '', username: '', password: '');

  OpdsSettings copyWith({String? baseUrl, String? username, String? password}) {
    return OpdsSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}

/// Normalizes a user-entered server address into a clean base URL: adds an
/// `http://` scheme if missing, drops trailing slashes, and strips a trailing
/// `/opds` (the client appends OPDS paths itself).
String normalizeOpdsUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) return '';
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.toLowerCase().endsWith('/opds')) {
    url = url.substring(0, url.length - 5);
  }
  return url;
}

/// Loads and saves the OPDS connection settings.
///
/// The server URL and username live in [SharedPreferences]; the password
/// lives in the iOS Keychain via [FlutterSecureStorage]. Installs that saved
/// the password to SharedPreferences before the Keychain move are migrated
/// on first load. Where the Keychain isn't available (unit tests, platforms
/// without the plugin) the password transparently falls back to
/// SharedPreferences so behaviour is unchanged.
class SettingsService {
  static const _kBaseUrl = 'opds_base_url';
  static const _kUsername = 'opds_username';
  static const _kPassword = 'opds_password';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kDailyGoal = 'daily_minute_goal';
  static const _kAutoDownloadNext = 'auto_download_next';
  static const _kAutoDownloadWifiOnly = 'auto_download_wifi_only';
  static const _kAutoDeleteFinished = 'auto_delete_finished';

  // first_unlock: readable after the first unlock following a reboot, so
  // background refresh/downloads don't lose auth while the phone is locked.
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<OpdsSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var password = await _readSecure(_kPassword);

    // One-time migration: older installs kept the password in plain
    // SharedPreferences. Move it into the Keychain and scrub the prefs copy.
    final legacy = prefs.getString(_kPassword);
    if (legacy != null) {
      if ((password == null || password.isEmpty) && legacy.isNotEmpty) {
        if (await _writeSecure(_kPassword, legacy)) {
          await prefs.remove(_kPassword);
        }
        password = legacy;
      } else if (password != null) {
        // Keychain already authoritative — scrub the stale prefs copy.
        await prefs.remove(_kPassword);
      }
      password ??= legacy;
    }

    return OpdsSettings(
      baseUrl: prefs.getString(_kBaseUrl) ?? '',
      username: prefs.getString(_kUsername) ?? '',
      password: password ?? '',
    );
  }

  Future<void> save(OpdsSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, settings.baseUrl);
    await prefs.setString(_kUsername, settings.username);
    if (await _writeSecure(_kPassword, settings.password)) {
      await prefs.remove(_kPassword);
    } else {
      // Keychain unavailable (tests / unsupported platform) — keep the old
      // SharedPreferences behaviour so settings still round-trip.
      await prefs.setString(_kPassword, settings.password);
    }
  }

  /// Reads [key] from secure storage; null when unset or unavailable.
  ///
  /// The catch is deliberately broad: depending on platform and plugin
  /// version an unavailable Keychain surfaces as `PlatformException`,
  /// `MissingPluginException`, or `UnimplementedError` (an `Error`, not an
  /// `Exception`). Any failure means "fall back to SharedPreferences", the
  /// pre-Keychain behaviour.
  Future<String?> _readSecure(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  /// Writes (or, for an empty value, deletes) [key] in secure storage.
  /// Returns false when secure storage isn't available (see [_readSecure]
  /// for why the catch is broad).
  Future<bool> _writeSecure(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True once the user has been through (or skipped) the first-launch
  /// onboarding welcome flow.
  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDone) ?? false;
  }

  Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  /// Daily reading-time goal in minutes. 0 means no goal set.
  Future<int> readDailyMinuteGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kDailyGoal) ?? 0;
  }

  Future<void> saveDailyMinuteGoal(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    if (minutes <= 0) {
      await prefs.remove(_kDailyGoal);
    } else {
      await prefs.setInt(_kDailyGoal, minutes);
    }
  }

  /// When true, finishing a volume (or syncing) pulls the next volume of an
  /// in-progress series so it's ready offline. Default on.
  Future<bool> autoDownloadNext() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoDownloadNext) ?? true;
  }

  Future<void> setAutoDownloadNext(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoDownloadNext, value);
  }

  /// When true, auto-download only runs on Wi-Fi/ethernet, never cellular.
  /// Default on.
  Future<bool> autoDownloadWifiOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoDownloadWifiOnly) ?? true;
  }

  Future<void> setAutoDownloadWifiOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoDownloadWifiOnly, value);
  }

  /// When true, a volume's downloaded EPUB is removed once it's been finished
  /// and the reader has moved on to a later volume. Default OFF — opt-in.
  Future<bool> autoDeleteFinished() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoDeleteFinished) ?? false;
  }

  Future<void> setAutoDeleteFinished(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoDeleteFinished, value);
  }
}
