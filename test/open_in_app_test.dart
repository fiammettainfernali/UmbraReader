// Handing a volume to another app to OPEN rather than to share.
//
// The bug behind this: Natural Reader registers EPUB under ACTION_VIEW and
// only plain text under ACTION_SEND, so sharing a volume offered Bluetooth
// and Gmail while the one app that could read the book aloud was absent from
// the sheet entirely.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/services/open_in_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory staging;
  late File epub;
  late List<MethodCall> calls;
  bool? answer;

  const channel = MethodChannel('umbra/open_in');

  setUp(() {
    staging = Directory.systemTemp.createTempSync('umbra_open_in');
    epub = File('${staging.path}/source.epub')
      ..writeAsBytesSync(List<int>.filled(64, 7));
    calls = [];
    answer = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<bool> open({String title = 'Supreme Magus Vol 3'}) =>
      const OpenInApp().openEpub(epub, title: title, stagingParent: staging);

  test('the volume is staged and offered as an EPUB', () async {
    expect(await open(), isTrue);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'open');
    final args = calls.single.arguments as Map;
    expect(args['mimeType'], 'application/epub+zip');

    final staged = File(args['path'] as String);
    expect(staged.existsSync(), isTrue);
    expect(
      staged.lengthSync(),
      epub.lengthSync(),
      reason: 'the receiving app gets the whole volume',
    );
  });

  test('it is named after the book, not after the file on disk', () async {
    // Reader apps list what they are handed by filename, so this is the
    // difference between a library of titles and a library of b1-v1.epub.
    await open();

    final path = (calls.single.arguments as Map)['path'] as String;
    expect(path, endsWith('Supreme Magus Vol 3.epub'));
  });

  test('a title that cannot be a filename still arrives', () async {
    await open(title: 'Re:Zero / Vol 2 <Arc 4>');

    final path = (calls.single.arguments as Map)['path'] as String;
    // Split on either separator: the service joins with '/', which is
    // right on Android and not what this host uses.
    final name = path.split(RegExp(r'[\/]')).last;
    expect(name, endsWith('.epub'));
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains(':')));
    expect(name, isNot(contains('<')));
  });

  test('an enormous title is capped rather than rejected by the OS', () async {
    await open(title: 'A' * 400);

    final path = (calls.single.arguments as Map)['path'] as String;
    // Split on either separator: the service joins with '/', which is
    // right on Android and not what this host uses.
    final name = path.split(RegExp(r'[\/]')).last;
    expect(name.length, lessThanOrEqualTo(85));
  });

  test('each handover clears the last one', () async {
    await open(title: 'First Book');
    final first = File((calls.single.arguments as Map)['path'] as String);
    expect(first.existsSync(), isTrue);

    calls.clear();
    await open(title: 'Second Book');

    expect(
      first.existsSync(),
      isFalse,
      reason: 'a whole volume per handover would accumulate in cache',
    );
    expect(
      File((calls.single.arguments as Map)['path'] as String).existsSync(),
      isTrue,
    );
  });

  test('a volume that is not downloaded is not offered', () async {
    epub.deleteSync();

    expect(await open(), isFalse);
    expect(calls, isEmpty, reason: 'nothing to hand over');
  });

  test('"nothing can open this" is reported, not swallowed', () async {
    // The caller falls back to the share sheet on false, so this answer has
    // to come back truthfully rather than as an optimistic true.
    answer = false;
    expect(await open(), isFalse);

    answer = null;
    expect(await open(), isFalse);
  });

  test(
    'on iOS it declines, because the share sheet is the mechanism',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(await open(), isFalse);
      expect(calls, isEmpty, reason: 'no Android bridge to call');
    },
  );
}
