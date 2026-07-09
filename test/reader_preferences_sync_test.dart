// Reader-settings sync: taste settings travel across devices; settings
// that describe the device in hand (TV mode, reading mode, orientation,
// screen geometry) must NOT — turning on TV mode on the iPad shouldn't
// flip the phone into TV mode.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/reader_preferences.dart';

void main() {
  test('merge applies taste settings but never device-local ones', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // This phone: scroll mode, TV mode off, dark theme, 18pt.
      'reader_mode': 'scroll',
      'reader_tv_mode': false,
      'reader_theme': 'dark',
      'reader_font_size': 18.0,
      'reader_font': '',
      'reader_settings_modified': '2026-07-01T10:00:00.000',
    });

    // The iPad pushed newer settings: TV mode on, paged, sepia, Literata,
    // 22pt.
    final blob = jsonEncode({
      'modifiedAt': '2026-07-03T10:00:00.000',
      'values': {
        'reader_mode': 'paged',
        'reader_tv_mode': true,
        'reader_theme': 'sepia',
        'reader_font': 'Literata',
        'reader_font_size': 22.0,
      },
    });
    final changed = await ReaderPreferences().mergeSyncBlob(blob);
    expect(changed, isTrue);

    final prefs = await SharedPreferences.getInstance();
    // Taste followed the cloud…
    expect(prefs.getString('reader_theme'), 'sepia');
    expect(prefs.getString('reader_font'), 'Literata');
    // …but the device kept its own layout and geometry.
    expect(prefs.getString('reader_mode'), 'scroll');
    expect(prefs.getBool('reader_tv_mode'), isFalse);
    expect(prefs.getDouble('reader_font_size'), 18.0);
  });

  test('stale cloud settings do not merge at all', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_theme': 'dark',
      'reader_settings_modified': '2026-07-03T10:00:00.000',
    });
    final blob = jsonEncode({
      'modifiedAt': '2026-07-01T10:00:00.000',
      'values': {'reader_theme': 'sepia'},
    });
    expect(await ReaderPreferences().mergeSyncBlob(blob), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('reader_theme'), 'dark');
  });
}
