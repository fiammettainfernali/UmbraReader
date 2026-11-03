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

  /// How many open screens want everything still. See [HoldsMotionStill].
  static final ValueNotifier<int> stillScreens = ValueNotifier(0);

  static bool isReduced(BuildContext context) =>
      MediaQuery.of(context).disableAnimations || reduceAnimations.value;
}

/// For a screen where the embers would only spend battery: the reader, whose
/// page covers them and where the phone may sit open for hours, and the web
/// views. Movement stays stopped for as long as the screen is open, including
/// behind anything opened from it.
mixin HoldsMotionStill<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    AppMotion.stillScreens.value++;
  }

  @override
  void dispose() {
    AppMotion.stillScreens.value--;
    super.dispose();
  }
}
