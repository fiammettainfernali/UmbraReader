import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_settings.dart';
import '../models/volume.dart';
import 'cloud_sync_service.dart';
import 'tts_engine.dart';
import 'tts_skip.dart';

/// Loads and saves the reader's [ReaderSettings] via [SharedPreferences].
///
/// Settings are stored two ways: a single global set under un-prefixed keys
/// (used by default for every book) and an optional *per-volume override*
/// stored under keys prefixed with the volume's key. When an override exists
/// for a volume, opening it loads those settings instead — handy for the
/// odd book that reads better with, say, a different font or wider margins.
class ReaderPreferences {
  static const _kMode = 'reader_mode';
  static const _kThemeId = 'reader_theme';
  static const _kFontFamily = 'reader_font';
  static const _kFontSize = 'reader_font_size';
  static const _kLineHeight = 'reader_line_height';
  static const _kMargin = 'reader_margin';
  static const _kSpeechRate = 'reader_speech_rate';
  static const _kVoiceName = 'reader_voice_name';
  static const _kVoiceLocale = 'reader_voice_locale';
  static const _kBoldText = 'reader_bold_text';
  static const _kItalicText = 'reader_italic_text';
  static const _kBrightness = 'reader_brightness';
  static const _kTextAlign = 'reader_text_align';
  static const _kAutoScroll = 'reader_auto_scroll';
  static const _kOrientation = 'reader_orientation';
  static const _kTvMode = 'reader_tv_mode';
  static const _kCenteredColumn = 'reader_centered_column';
  static const _kKeepAwake = 'reader_keep_awake';
  static const _kAutoPageSeconds = 'reader_auto_page_seconds';
  static const _kTtsEngine = 'reader_tts_engine';
  static const _kTtsServerUrl = 'reader_tts_server_url';
  static const _kTtsServerToken = 'reader_tts_server_token';
  static const _kTtsSkips = 'reader_tts_skips';

  /// Marker key telling us a per-volume override has been opted into.
  static const _kOverrideMarker = 'reader_override_marker';

  /// When the global reader settings were last changed — drives whole-set
  /// last-write-wins when merging the iCloud copy.
  static const _kGlobalModified = 'reader_settings_modified';

  /// The global setting keys, in the order they serialise for sync.
  static const _globalKeys = [
    _kMode, _kThemeId, _kFontFamily, _kFontSize, _kLineHeight, _kMargin,
    _kSpeechRate, _kVoiceName, _kVoiceLocale, _kBoldText, _kItalicText,
    _kBrightness, _kTextAlign, _kAutoScroll, _kOrientation, _kTvMode,
    _kCenteredColumn, _kKeepAwake, _kAutoPageSeconds,
    _kTtsEngine, _kTtsServerUrl, _kTtsServerToken, _kTtsSkips,
  ];

  /// Settings that describe the DEVICE in hand rather than reading taste —
  /// layout mode, TV/spread mode, orientation lock, centred column, screen
  /// geometry (font size, margins), brightness, hands-free motion. These
  /// never merge in from iCloud: turning on TV mode on the iPad must not
  /// flip the phone into TV mode. (They still travel in the export for
  /// back-compat; the merge side ignores them.)
  static const _deviceLocalKeys = {
    _kMode,
    _kTvMode,
    _kOrientation,
    _kCenteredColumn,
    _kKeepAwake,
    _kBrightness,
    _kAutoScroll,
    _kAutoPageSeconds,
    _kFontSize,
    _kMargin,
  };

  /// Per-volume keys are global keys prefixed with this + the volume's id
  /// (e.g. `book:42/Lord-of-the-Mysteries-Vol-03.epub/reader_font_size`).
  String _volumePrefix(Volume v) => 'book:${v.seriesOpdsId}/${v.fileName}/';

  Future<ReaderSettings> load({Volume? volume}) async {
    final prefs = await SharedPreferences.getInstance();
    const d = ReaderSettings.defaults;
    final p = volume != null && prefs.getBool(
              '${_volumePrefix(volume)}$_kOverrideMarker',
            ) == true
        ? _volumePrefix(volume)
        : '';
    return ReaderSettings(
      mode: prefs.getString('$p$_kMode') == 'paged'
          ? ReadingMode.paged
          : ReadingMode.scroll,
      themeId: prefs.getString('$p$_kThemeId') ?? d.themeId,
      fontFamily: prefs.getString('$p$_kFontFamily') ?? d.fontFamily,
      fontSize: prefs.getDouble('$p$_kFontSize') ?? d.fontSize,
      lineHeight: prefs.getDouble('$p$_kLineHeight') ?? d.lineHeight,
      margin: prefs.getDouble('$p$_kMargin') ?? d.margin,
      speechRate: prefs.getDouble('$p$_kSpeechRate') ?? d.speechRate,
      voiceName: prefs.getString('$p$_kVoiceName') ?? d.voiceName,
      voiceLocale: prefs.getString('$p$_kVoiceLocale') ?? d.voiceLocale,
      boldText: prefs.getBool('$p$_kBoldText') ?? d.boldText,
      italicText: prefs.getBool('$p$_kItalicText') ?? d.italicText,
      brightness: prefs.getDouble('$p$_kBrightness') ?? d.brightness,
      textAlign: ReaderTextAlign.values.firstWhere(
        (a) => a.name == prefs.getString('$p$_kTextAlign'),
        orElse: () => d.textAlign,
      ),
      autoScroll: prefs.getBool('$p$_kAutoScroll') ?? d.autoScroll,
      orientation: ReaderOrientation.values.firstWhere(
        (o) => o.name == prefs.getString('$p$_kOrientation'),
        orElse: () => d.orientation,
      ),
      tvMode: prefs.getBool('$p$_kTvMode') ?? d.tvMode,
      centeredColumn: prefs.getBool('$p$_kCenteredColumn') ?? d.centeredColumn,
      keepAwake: prefs.getBool('$p$_kKeepAwake') ?? d.keepAwake,
      autoPageSeconds:
          prefs.getInt('$p$_kAutoPageSeconds') ?? d.autoPageSeconds,
      ttsEngine: TtsEngineKind.values.firstWhere(
        (e) => e.name == prefs.getString('$p$_kTtsEngine'),
        orElse: () => d.ttsEngine,
      ),
      ttsServerUrl: prefs.getString('$p$_kTtsServerUrl') ?? d.ttsServerUrl,
      ttsServerToken:
          prefs.getString('$p$_kTtsServerToken') ?? d.ttsServerToken,
      ttsSkips: parseTtsSkips(prefs.getString('$p$_kTtsSkips')),
    );
  }

  Future<void> save(ReaderSettings settings, {Volume? volume}) async {
    final prefs = await SharedPreferences.getInstance();
    final p = volume != null && await hasOverride(volume)
        ? _volumePrefix(volume)
        : '';
    await prefs.setString('$p$_kMode', settings.mode.name);
    await prefs.setString('$p$_kThemeId', settings.themeId);
    await prefs.setString('$p$_kFontFamily', settings.fontFamily);
    await prefs.setDouble('$p$_kFontSize', settings.fontSize);
    await prefs.setDouble('$p$_kLineHeight', settings.lineHeight);
    await prefs.setDouble('$p$_kMargin', settings.margin);
    await prefs.setDouble('$p$_kSpeechRate', settings.speechRate);
    await prefs.setString('$p$_kVoiceName', settings.voiceName);
    await prefs.setString('$p$_kVoiceLocale', settings.voiceLocale);
    await prefs.setBool('$p$_kBoldText', settings.boldText);
    await prefs.setBool('$p$_kItalicText', settings.italicText);
    await prefs.setDouble('$p$_kBrightness', settings.brightness);
    await prefs.setString('$p$_kTextAlign', settings.textAlign.name);
    await prefs.setBool('$p$_kAutoScroll', settings.autoScroll);
    await prefs.setString('$p$_kOrientation', settings.orientation.name);
    await prefs.setBool('$p$_kTvMode', settings.tvMode);
    await prefs.setBool('$p$_kCenteredColumn', settings.centeredColumn);
    await prefs.setBool('$p$_kKeepAwake', settings.keepAwake);
    await prefs.setInt('$p$_kAutoPageSeconds', settings.autoPageSeconds);
    await prefs.setString('$p$_kTtsEngine', settings.ttsEngine.name);
    await prefs.setString('$p$_kTtsServerUrl', settings.ttsServerUrl);
    await prefs.setString('$p$_kTtsServerToken', settings.ttsServerToken);
    await prefs.setString('$p$_kTtsSkips', encodeTtsSkips(settings.ttsSkips));
    // Only global changes participate in iCloud sync; per-volume overrides
    // stay on the device that set them.
    if (p.isEmpty) {
      await prefs.setString(
        _kGlobalModified,
        DateTime.now().toIso8601String(),
      );
      CloudSyncService().pushReaderSettings();
    }
  }

  // ── iCloud sync (see CloudSyncService) ─────────────────────────────────

  /// The global reader settings (and their last-modified time) as a JSON
  /// blob. Per-volume overrides are intentionally excluded.
  Future<String> exportSyncBlob() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, dynamic>{};
    for (final key in _globalKeys) {
      final v = prefs.get(key);
      if (v != null) values[key] = v;
    }
    return jsonEncode({
      'modifiedAt': prefs.getString(_kGlobalModified) ?? '',
      'values': values,
    });
  }

  /// Overwrites the global reader settings with the cloud copy when its
  /// modified time is newer. Returns true if local settings changed.
  Future<bool> mergeSyncBlob(String blob) async {
    if (blob.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    final cloudModified =
        DateTime.tryParse(decoded['modifiedAt'] as String? ?? '');
    if (cloudModified == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final localModified =
        DateTime.tryParse(prefs.getString(_kGlobalModified) ?? '');
    if (localModified != null && !cloudModified.isAfter(localModified)) {
      return false;
    }
    final values = decoded['values'];
    if (values is! Map) return false;
    for (final key in _globalKeys) {
      if (_deviceLocalKeys.contains(key)) continue; // this device's business
      final v = values[key];
      if (v is bool) {
        await prefs.setBool(key, v);
      } else if (v is int) {
        await prefs.setInt(key, v);
      } else if (v is double) {
        await prefs.setDouble(key, v);
      } else if (v is num) {
        await prefs.setDouble(key, v.toDouble());
      } else if (v is String) {
        await prefs.setString(key, v);
      }
    }
    await prefs.setString(_kGlobalModified, cloudModified.toIso8601String());
    return true;
  }

  static const _kSeriesVoicePrefix = 'series_voice:';

  /// The narrator chosen for a whole series (name, locale), or null if none.
  Future<(String, String)?> seriesVoice(int seriesId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kSeriesVoicePrefix$seriesId');
    if (raw == null || raw.isEmpty) return null;
    final sep = raw.indexOf('|');
    if (sep < 0) return (raw, '');
    return (raw.substring(0, sep), raw.substring(sep + 1));
  }

  /// Remembers [name]/[locale] as the narrator for [seriesId]. Clearing to an
  /// empty voice removes the per-series override.
  Future<void> saveSeriesVoice(
    int seriesId,
    String name,
    String locale,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kSeriesVoicePrefix$seriesId';
    if (name.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, '$name|$locale');
    }
  }

  Future<bool> hasOverride(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${_volumePrefix(volume)}$_kOverrideMarker') == true;
  }

  /// Seeds a per-volume override with [settings] and flips the marker on.
  /// Subsequent saves go to this volume's keys until the override is cleared.
  Future<void> enableOverride(Volume volume, ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${_volumePrefix(volume)}$_kOverrideMarker',
      true,
    );
    await save(settings, volume: volume);
  }

  /// Removes the per-volume override and all of its stored keys, so the
  /// volume falls back to the global settings.
  Future<void> clearOverride(Volume volume) async {
    final prefs = await SharedPreferences.getInstance();
    final p = _volumePrefix(volume);
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(p)) {
        await prefs.remove(key);
      }
    }
  }
}
