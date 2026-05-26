import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/settings_service.dart';

void main() {
  runApp(const UmbraReaderApp());
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

  /// A single dark theme for now. Phase 4 replaces this with a full theme
  /// engine (multiple presets, adjustable colors / fonts / spacing).
  ThemeData _buildTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        // A muted dusk purple — fitting for "umbra" (shadow).
        seedColor: const Color(0xFF8B7BC4),
        brightness: Brightness.dark,
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
