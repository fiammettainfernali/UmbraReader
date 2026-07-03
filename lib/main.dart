import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'screens/library_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/cloud_sync_service.dart';
import 'services/custom_theme_store.dart';
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
  // Wire iCloud sync (reading progress / collections / rec feedback). The
  // initial pull runs in the background; no-ops where iCloud is unavailable.
  await CloudSyncService().initialize();

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
      title: 'Umbra Reader',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const _RootGate(),
    );
  }

  /// The app's "comfy witchy library" theme: a deep dusk-plum dark scheme
  /// with a warm candlelight-amber accent, an elegant serif for headings, and
  /// soft rounded surfaces. (This is the app chrome — the *reader* still uses
  /// its own page themes.)
  ThemeData _buildTheme() {
    final scheme =
        ColorScheme.fromSeed(
          // A muted dusk purple — fitting for "umbra" (shadow).
          seedColor: const Color(0xFF8B7BC4),
          brightness: Brightness.dark,
        ).copyWith(
          // Warm candlelight gold for accents (section motifs, highlights).
          tertiary: const Color(0xFFE3B873),
          onTertiary: const Color(0xFF2A1F0A),
        );

    final base = ThemeData(
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF14111C), // deep dusk
    );

    // A warm book serif for headings/titles (the dark-academia library feel),
    // using an iOS system font so it needs no download and works offline; body
    // and labels stay in the clean default for legibility.
    const heading = 'Georgia';
    TextStyle? h(TextStyle? s) => s?.copyWith(fontFamily: heading);
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
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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
    return const LibraryScreen();
  }
}
