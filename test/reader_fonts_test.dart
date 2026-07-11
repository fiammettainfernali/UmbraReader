// Bundled reader fonts must actually ship: a font offered in the picker but
// whose asset is missing/misnamed silently falls back to the system font with
// no error. Guard the wiring (pubspec family + on-disk face files).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/widgets/reader_settings_sheet.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('every offered font family is declared in pubspec', () {
    for (final family in kReaderFonts.where((f) => f.isNotEmpty)) {
      expect(
        pubspec.contains('family: $family'),
        isTrue,
        reason: '"$family" is in the picker but has no pubspec fonts entry',
      );
    }
  });

  test('OpenDyslexic ships all four faces and its licence', () {
    expect(kReaderFonts, contains('OpenDyslexic'));
    const faces = [
      'OpenDyslexic-Regular.otf',
      'OpenDyslexic-Italic.otf',
      'OpenDyslexic-Bold.otf',
      'OpenDyslexic-Bold-Italic.otf',
    ];
    for (final face in faces) {
      expect(
        File('assets/fonts/$face').existsSync(),
        isTrue,
        reason: '$face is referenced but not bundled',
      );
      expect(pubspec.contains(face), isTrue, reason: '$face not in pubspec');
    }
    expect(
      File('assets/fonts/OFL-OpenDyslexic.txt').existsSync(),
      isTrue,
      reason: 'the OFL licence must ship alongside the font',
    );
  });
}
