import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/app_motion.dart';
import 'services/cloud_sync_service.dart';
import 'services/custom_theme_store.dart';
import 'services/pro_service.dart';
import 'services/reader_preferences.dart';
import 'services/reminder_service.dart';
import 'services/settings_service.dart';

/// Sentry crash-reporting DSN, baked in at build time via
/// `--dart-define=SENTRY_DSN=…` (a Codemagic env var). Empty in local/dev
/// builds and on CI until the var is configured — in which case crash
/// reporting is entirely disabled and no SDK code runs.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load user-defined reading themes into the in-memory registry so
  // readerThemeById can find them synchronously.
  await CustomThemeStore().initialize();
  // Known before the first frame, so nothing moves once if it's switched off.
  AppMotion.reduceAnimations.value =
      (await ReaderPreferences().load()).reduceAnimations;
  // Load the Pro entitlement (build-flag or persisted purchase).
  await ProService().initialize();
  // Wire iCloud sync (reading progress / collections / rec feedback). The
  // initial pull runs in the background; no-ops where iCloud is unavailable.
  // iCloud sync is a Pro feature; free builds stay local-only.
  if (ProService().isPro.value) {
    await CloudSyncService().initialize();
  }
  // Re-arm the reading-reminder schedule (a no-op unless opted in). Not
  // awaited: nothing on screen depends on it, and launch shouldn't wait.
  unawaited(ReminderService().refresh());

  if (_sentryDsn.isEmpty) {
    runApp(const UmbraReaderApp());
    return;
  }
  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    // Crashes and uncaught errors only — no performance tracing, no session
    // replay, and never any personally identifying info. What the user
    // reads stays on the device.
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0;
    options.attachScreenshot = false;
    // (attachViewHierarchy is experimental and already defaults to off.)
  }, appRunner: () => runApp(const UmbraReaderApp()));
}

class UmbraReaderApp extends StatelessWidget {
  const UmbraReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hawthorne Codex',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const _RootGate(),
    );
  }

  /// The Hawthorne Codex look, matching the desktop program: mostly black and
  /// red, an elegant serif for headings, and soft rounded surfaces. (This is
  /// the app chrome — the *reader* still uses its own page themes.)
  ThemeData _buildTheme() {
    // The strong red fills buttons, with white on it. Text and icons use the
    // lighter one, because the strong red is too dim to read at small sizes.
    const red = Color(0xFFE5121F);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: red,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFFF4B4B),
          onPrimary: const Color(0xFF2A0306),
          primaryContainer: const Color(0xFF5A0710),
          onPrimaryContainer: const Color(0xFFFFD9D9),
          secondary: const Color(0xFFFF8A80),
          secondaryContainer: const Color(0xFF47090F),
          onSecondaryContainer: const Color(0xFFFFD9D9),
          tertiary: const Color(0xFFFF7A6B),
          onTertiary: const Color(0xFF2A0306),
          surface: const Color(0xFF0C0608),
          onSurface: const Color(0xFFF7EFEF),
          onSurfaceVariant: const Color(0xFFCDBCBD),
          outline: const Color(0xFF9A8486),
          outlineVariant: const Color(0xFF3A2326),
          surfaceContainerLowest: const Color(0xFF080304),
          surfaceContainerLow: const Color(0xFF120709),
          surfaceContainer: const Color(0xFF180A0D),
          surfaceContainerHigh: const Color(0xFF211014),
          surfaceContainerHighest: const Color(0xFF2C161A),
        );

    final base = ThemeData(
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF060304),
    );

    // A warm book serif for headings/titles (the dark-academia library feel),
    // using an iOS system font so it needs no download and works offline; body
    // and labels stay in the clean default for legibility.
    const heading = 'Georgia';
    // Android ships no Georgia, and an unresolvable family falls back to the
    // default sans without complaint — the serif simply disappears and the
    // app looks like a different one. Lora is already bundled for the reader,
    // so naming it here costs no bytes and leaves iOS on Georgia untouched.
    const headingFallback = ['Lora'];
    TextStyle? h(TextStyle? s) =>
        s?.copyWith(fontFamily: heading, fontFamilyFallback: headingFallback);
    final t = base.textTheme;
    final textTheme = t.copyWith(
      displayLarge: h(t.displayLarge),
      displayMedium: h(t.displayMedium),
      displaySmall: h(t.displaySmall),
      headlineLarge: h(t.headlineLarge),
      headlineMedium: h(t.headlineMedium),
      headlineSmall: h(t.headlineSmall),
      titleLarge: h(t.titleLarge)?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: h(t.titleMedium)?.copyWith(fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: base.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: heading,
          fontFamilyFallback: headingFallback,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: red,
          foregroundColor: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: red,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: red,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        modalBackgroundColor: scheme.surfaceContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        actionTextColor: scheme.primary,
      ),
    );
  }
}

/// Picks the right home screen on launch — onboarding for fresh installs
/// (no server configured and the welcome flow has never been seen), library
/// for everyone else.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _resolving = true;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final service = SettingsService();
    final settings = await service.load();
    final seen = await service.hasSeenOnboarding();
    if (!mounted) return;
    setState(() {
      _showOnboarding = !settings.isConfigured && !seen;
      _resolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showOnboarding) {
      return OnboardingScreen(
        onFinished: () => setState(() => _showOnboarding = false),
      );
    }
    return const HomeShell();
  }
}
