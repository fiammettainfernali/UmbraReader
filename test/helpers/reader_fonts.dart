// Real reading fonts for the tests that compare measurement against render.
//
// Without this the whole comparison is worthless. The font `flutter test`
// falls back to has one set of metrics for every weight -- bold and regular
// lay out to the identical width -- so a test that renders bold text and
// measures regular text passes, and goes on passing however far apart the
// two drift. That is exactly how a paged-mode overflow reached a phone:
// every render-vs-measure test in the suite was blind to weight.
//
// Literata is already bundled for the reader and ships a real Bold, so
// loading it costs nothing and gives the comparison something to see.

import 'dart:io';

import 'package:flutter/services.dart';

/// The family these tests set on [ReaderSettings.fontFamily]. Naming it
/// explicitly matters: the reader's default is the empty string, which
/// resolves to the platform font -- the weight-blind one -- so a test left
/// on the default measures nothing.
const String kTestReaderFont = 'Literata';

Future<ByteData> _bytes(String name) async {
  final data = await File('assets/fonts/$name').readAsBytes();
  return ByteData.view(Uint8List.fromList(data).buffer);
}

/// Registers [kTestReaderFont] with its real regular and bold faces.
/// Call from `setUpAll` after `TestWidgetsFlutterBinding.ensureInitialized`.
Future<void> loadReaderFonts() async {
  final loader = FontLoader(kTestReaderFont)
    ..addFont(_bytes('Literata-Regular.ttf'))
    ..addFont(_bytes('Literata-Bold.ttf'))
    ..addFont(_bytes('Literata-Italic.ttf'));
  await loader.load();
}
