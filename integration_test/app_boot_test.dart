// Does the app actually start on this platform?
//
// Everything else is measured in pieces: the host suite stubs the plugins,
// and `flutter build apk` only proves the code compiles. Nothing until here
// runs the real startup path — drift opening a native SQLite file,
// path_provider resolving a directory, secure storage reaching the Keystore,
// the notification plugin initialising. Each of those is a platform binding
// that a widget test replaces with a fake.
//
// Needs a device or emulator:
//   flutter test integration_test/app_boot_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/main.dart' as app;
import 'package:umbra_reader/screens/home_shell.dart';
import 'package:umbra_reader/screens/onboarding_screen.dart';
import 'package:umbra_reader/services/settings_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the real startup path reaches a screen', (tester) async {
    // main() itself — theme store, Pro entitlement, sync wiring, reminder
    // rearm. A platform binding that throws here takes the launch with it.
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 30));

    // Either destination is a healthy boot: onboarding on a fresh install,
    // the library once a server is configured. What matters is that the root
    // gate resolved at all rather than sitting on its spinner.
    final landed =
        find.byType(OnboardingScreen).evaluate().isNotEmpty ||
        find.byType(HomeShell).evaluate().isNotEmpty;
    expect(
      landed,
      isTrue,
      reason: 'startup finished but showed neither onboarding nor the library',
    );
  });

  testWidgets('drift opens a real database file and answers', (tester) async {
    // The likeliest native failure on a new platform: drift ships its own
    // SQLite, and a missing NDK build of it fails at the first query rather
    // than at compile time.
    const key = 'integration_boot_probe';
    final db = AppDatabase.instance;

    await db.kvSet(key, 'written-on-device');
    expect(await db.kvGet(key), 'written-on-device');

    // Overwrite, to prove this is a real store and not a write-once cache.
    await db.kvSet(key, 'rewritten');
    expect(await db.kvGet(key), 'rewritten');
  });

  testWidgets('settings survive a round-trip through platform storage', (
    tester,
  ) async {
    // SharedPreferences plus the Keystore-backed secure store. The password
    // is the half that has no test double on the device.
    final service = SettingsService();
    const settings = OpdsSettings(
      baseUrl: 'http://192.168.1.42:8765',
      username: 'reader',
      password: 'device-round-trip',
    );

    await service.save(settings);
    final loaded = await service.load();

    expect(loaded.baseUrl, settings.baseUrl);
    expect(loaded.username, settings.username);
    expect(loaded.password, settings.password,
        reason: 'the password did not survive the platform secure store');
    expect(loaded.passwordLost, isFalse);
  });
}
