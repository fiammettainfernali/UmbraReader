// The reader now speaks up when a lookup goes nowhere, and it decides that
// from this return value. iOS always has a dictionary; Android has none of
// its own and borrows whatever is installed, so false is a state that
// actually happens there rather than a theoretical branch.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/dictionary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('umbra/define');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reports false where there is no bridge at all', () async {
    // No handler installed: the platform answers MissingPluginException,
    // which is exactly what Android did before the bridge existed.
    expect(await DictionaryService().define('sesquipedalian'), isFalse);
  });

  test('reports false when nothing on the device handles the lookup', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await DictionaryService().define('sesquipedalian'), isFalse);
  });

  test('reports true when a dictionary opened', () async {
    late String seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'define');
      seen = (call.arguments as Map)['term'] as String;
      return true;
    });

    expect(await DictionaryService().define('  sesquipedalian  '), isTrue);
    expect(seen, 'sesquipedalian', reason: 'the term is trimmed on the way');
  });

  test('an empty term never reaches the platform', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return true;
    });

    expect(await DictionaryService().define('   '), isFalse);
    expect(called, isFalse);
  });

  test('a platform error is a false, not a crash mid-read', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'no_activity'),
    );
    expect(await DictionaryService().define('sesquipedalian'), isFalse);
  });
}
