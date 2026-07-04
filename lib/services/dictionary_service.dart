import 'package:flutter/services.dart';

/// Opens the iOS system dictionary (UIReferenceLibraryViewController) for a
/// term — the "Define" action on selected reader text. Bridged in
/// `ios/Runner/AppDelegate.swift` over `umbra/define`.
///
/// Safe everywhere: on platforms without the bridge (tests, Android,
/// desktop) [define] simply returns false.
class DictionaryService {
  static const MethodChannel _channel = MethodChannel('umbra/define');

  Future<bool> define(String term) async {
    final clean = term.trim();
    if (clean.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('define', {'term': clean}) ??
          false;
    } on Exception {
      return false;
    } on Error {
      return false;
    }
  }
}
