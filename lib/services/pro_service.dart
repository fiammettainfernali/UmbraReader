import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this build ships with Pro permanently unlocked.
///
/// Defaults to TRUE: every build is fully unlocked until the App Store
/// launch flips it. The public release pipeline passes
/// `--dart-define=UMBRA_PRO=false` to turn the gate on; the developer's own
/// Codemagic pipeline keeps the default (or passes true explicitly), so dev
/// builds can never lock their owner out. See codemagic.yaml.
const bool kBuiltInPro = bool.fromEnvironment('UMBRA_PRO', defaultValue: true);

/// The Umbra Pro entitlement: one-time unlock for the power-user feature
/// set (custom themes, full-library search, stats & goals, Markdown export,
/// iCloud sync, collections, TV mode).
///
/// Sources, in order: the build-time [kBuiltInPro] flag, then a persisted
/// purchase flag. The StoreKit purchase flow (a later slice) sets the
/// persisted flag via [markPurchased]; nothing else in the app talks to the
/// store directly.
class ProService {
  ProService._();
  static final ProService instance = ProService._();
  factory ProService() => instance;

  static const _kPurchased = 'pro_unlocked';

  /// Reactive entitlement — gates listen to this so the UI unlocks the
  /// moment a purchase completes.
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(kBuiltInPro);

  /// Loads the persisted purchase flag. Call once at startup; cheap.
  Future<void> initialize() async {
    if (kBuiltInPro) return; // already unlocked, nothing to load
    final prefs = await SharedPreferences.getInstance();
    isPro.value = prefs.getBool(_kPurchased) ?? false;
  }

  /// Records a completed (or restored) purchase.
  Future<void> markPurchased() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPurchased, true);
    isPro.value = true;
  }
}
