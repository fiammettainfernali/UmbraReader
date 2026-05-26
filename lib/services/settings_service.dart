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

/// Loads and saves the OPDS connection settings via [SharedPreferences].
///
/// Note: the password is stored in plain SharedPreferences. For a personal
/// LAN reader app that is an acceptable tradeoff; if stronger protection is
/// ever wanted, swap in `flutter_secure_storage`.
class SettingsService {
  static const _kBaseUrl = 'opds_base_url';
  static const _kUsername = 'opds_username';
  static const _kPassword = 'opds_password';
  static const _kOnboardingDone = 'onboarding_done';

  Future<OpdsSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return OpdsSettings(
      baseUrl: prefs.getString(_kBaseUrl) ?? '',
      username: prefs.getString(_kUsername) ?? '',
      password: prefs.getString(_kPassword) ?? '',
    );
  }

  Future<void> save(OpdsSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, settings.baseUrl);
    await prefs.setString(_kUsername, settings.username);
    await prefs.setString(_kPassword, settings.password);
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
}
