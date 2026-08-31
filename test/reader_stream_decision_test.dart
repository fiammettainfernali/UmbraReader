// When does opening a book read from the server?
//
// Only the series screen passes stream:true. Continue reading, a search
// hit, a note, the next volume and a finished volume that auto-delete
// removed all open the reader with no flag — and every one of them used
// to die on "This volume is not downloaded", stranding books that had
// been read perfectly well by streaming.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/screens/reader_screen.dart';

void main() {
  test('an explicit request streams even when a copy is on the device', () {
    // "Read without downloading" means what it says.
    expect(
      ReaderScreen.shouldStream(requested: true, hasLocalFile: true),
      isTrue,
    );
  });

  test('a downloaded book opens from the file', () {
    // The common case, and the one that must not start using the network.
    expect(
      ReaderScreen.shouldStream(requested: false, hasLocalFile: true),
      isFalse,
    );
  });

  test('no file and no request still streams', () {
    // The regression. Resuming from Continue reading carries no flag, and
    // refusing it strands every streamed book the moment you leave it.
    expect(
      ReaderScreen.shouldStream(requested: false, hasLocalFile: false),
      isTrue,
    );
  });
}
