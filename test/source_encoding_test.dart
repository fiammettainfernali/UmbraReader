// No source file may contain mojibake.
//
// UTF-8 text read back as Latin-1 and re-saved turns an em dash into two
// characters, an apostrophe into three, a middle dot into two. The bytes
// stay valid, the file compiles, the analyzer is happy, and the damage
// surfaces somewhere else entirely — a progress label reading
// "40 of 486 series  <mangled>  8%", found by a test that had nothing to do
// with the file that was edited.
//
// It happened three times in one session, and each repair only fixed the
// sequence that had been noticed. This catches all of them at once, in the
// file that actually contains them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The tell-tales, built from code points rather than written out.
///
/// Spelling them literally would put them in this file, and the check would
/// then flag itself — which is exactly what the first version did.
///
/// Each is a common punctuation mark whose UTF-8 bytes have been decoded as
/// Latin-1: the lead byte of the sequence lands in the Latin-1 supplement,
/// followed by whatever the continuation byte decoded to.
final _mojibake = <String>[
  String.fromCharCodes([0x00E2, 0x20AC]), // em dash, quotes, apostrophe
  String.fromCharCodes([0x00C2, 0x00B7]), // middle dot
  String.fromCharCodes([0x00C2, 0x00AB]), // guillemets
  String.fromCharCodes([0x00C3, 0x00A9]), // e-acute
];

void main() {
  test('no source file contains mis-decoded text', () {
    final offenders = <String>[];
    for (final dir in ['lib', 'test']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Read as UTF-8: reading it any other way would hide exactly the
        // corruption being looked for.
        final text = entity.readAsStringSync();
        for (final marker in _mojibake) {
          if (text.contains(marker)) {
            offenders.add(entity.path);
            break;
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'These files were saved with the wrong encoding. Read them as '
          'UTF-8 and write them back as UTF-8 without a BOM.',
    );
  });

  test('the check would notice if it were broken', () {
    // A guard that can never fire is worse than none: it reads as proof.
    final mangled = 'a ${String.fromCharCodes([0x00E2, 0x20AC, 0x201D])} b';
    expect(_mojibake.any(mangled.contains), isTrue);

    final dotted = '40 of 486  ${String.fromCharCodes([0x00C2, 0x00B7])}  8%';
    expect(_mojibake.any(dotted.contains), isTrue);

    // And healthy text is left alone.
    expect(_mojibake.any('a — b  ·  ok'.contains), isFalse);
  });
}
