import 'package:flutter/widgets.dart';

/// Whether the app's own movement should stop: the phone's Reduce Motion, or
/// the "Reduce animations" switch in the reader's settings.
///
/// The reader answers this for itself from the settings it holds. Everything
/// outside it reads them from here, so the switch doesn't have to be turned on
/// in two places.
class AppMotion {
  AppMotion._();

  /// The saved switch, kept current by [ReaderPreferences].
  static final ValueNotifier<bool> reduceAnimations = ValueNotifier(false);

  static bool isReduced(BuildContext context) =>
      MediaQuery.of(context).disableAnimations || reduceAnimations.value;
}
