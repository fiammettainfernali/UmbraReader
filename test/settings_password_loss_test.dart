// A restore onto new hardware brings the OPDS server and username back but
// not the password: the Keystore key that encrypted it never left the old
// device. The account then looks configured and answers every request with
// 401. These tests pin the signal that tells the two states apart.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/settings_service.dart';

void main() {
  test('a password that was saved but no longer reads back is reported lost', () async {
    // The shape a restore leaves behind: server and username present, the
    // marker saying a password once existed, and no password anywhere.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'opds_base_url': 'http://192.168.1.42:8765',
      'opds_username': 'reader',
      'opds_password_saved': true,
    });

    final settings = await SettingsService().load();

    expect(settings.passwordLost, isTrue);
    expect(settings.isConfigured, isTrue, reason: 'it still looks set up');
    expect(settings.password, isEmpty);
  });

  test('a server that never had a password is not reported lost', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'opds_base_url': 'http://192.168.1.42:8765',
      'opds_username': '',
    });

    final settings = await SettingsService().load();

    expect(settings.passwordLost, isFalse);
  });

  test('a readable password adopts the marker, so the next loss is caught', () async {
    // An install predating the marker: the password is there, nothing records
    // that fact yet. The first load has to write the baseline itself.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'opds_base_url': 'http://192.168.1.42:8765',
      'opds_username': 'reader',
      'opds_password': 'hunter2',
    });

    final first = await SettingsService().load();
    expect(first.passwordLost, isFalse);
    expect(first.password, 'hunter2');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('opds_password_saved'), isTrue,
        reason: 'the baseline was adopted on the way past');
  });
}
