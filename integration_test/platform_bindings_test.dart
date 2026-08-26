// The Android fixes that were reasoned about rather than run.
//
// Three of them were invisible by construction: the notification plugin
// reports a failed initialisation by quietly refusing to do anything later,
// and a method channel that was never registered is indistinguishable, from
// Dart, from one that answered "no". Reasoning got them written; only a real
// platform can say whether they were right.
//
// Needs a device or emulator:
//   flutter test integration_test/platform_bindings_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:umbra_reader/services/dictionary_service.dart';
import 'package:umbra_reader/services/reminder_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('reminders', () {
    testWidgets('the plugin and timezone database initialise', (tester) async {
      // Android needs its own AndroidInitializationSettings with a default
      // icon. Without them this returns false and every reminder afterwards
      // is a no-op that reports nothing.
      final service = ReminderService();
      service.resetForTest();

      expect(
        await service.ensureReadyForTest(),
        isTrue,
        reason: 'the notification plugin did not come up on this platform',
      );
    });

    testWidgets('refresh runs the full path without throwing', (tester) async {
      // Reminders are off in a fresh install, so this exercises init and the
      // cancel sweep — both of which reach the platform channel.
      await expectLater(ReminderService().refresh(), completes);
    });
  });

  group('the define bridge', () {
    const channel = MethodChannel('umbra/define');

    testWidgets('the channel is actually registered', (tester) async {
      // An empty term is answered before the intent is built, so this proves
      // registration without launching a chooser over the test run.
      //
      // This has to go through the raw channel rather than DictionaryService:
      // the service catches MissingPluginException and returns false, which
      // is the same answer it gives when the bridge is present and simply
      // found no dictionary. Only the exception tells the two apart.
      try {
        final answered = await channel.invokeMethod<bool>('define', {
          'term': '',
        });
        expect(answered, isFalse);
      } on MissingPluginException {
        fail('umbra/define is not registered — MainActivity never wired it');
      }
    });

    testWidgets('it is our handler, not an accident', (tester) async {
      // The handler answers `define` and nothing else. If some other plugin
      // had claimed the channel name, this would come back implemented.
      await expectLater(
        channel.invokeMethod<bool>('not_a_real_method'),
        throwsA(isA<MissingPluginException>()),
      );
    });

    testWidgets('a real lookup answers instead of hanging', (tester) async {
      // Deliberately not asserting which answer. Whether anything handles
      // PROCESS_TEXT depends on what the image ships, and pinning that would
      // be a test about the emulator rather than about the bridge. What the
      // reader needs is a definite answer it can act on.
      expect(await DictionaryService().define('sesquipedalian'), isA<bool>());
    });
  });
}
