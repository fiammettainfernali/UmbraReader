import 'package:flutter/material.dart';

import '../services/opds_client.dart';
import '../services/settings_service.dart';

/// Friendly first-launch flow: introduces the app and walks the user through
/// connecting to their Novel Grabber OPDS server. Shown only once — after
/// the user finishes (or skips), [SettingsService.markOnboardingSeen] keeps
/// the library screen as the home thereafter.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Called after the user connects or skips — host should swap in the
  /// library screen.
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _settingsService = SettingsService();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _testing = false;
  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  OpdsSettings _currentSettings() => OpdsSettings(
    baseUrl: normalizeOpdsUrl(_urlController.text),
    username: _usernameController.text.trim(),
    password: _passwordController.text,
  );

  Future<void> _testConnection() async {
    final settings = _currentSettings();
    if (!settings.isConfigured) {
      _snack('Enter a server address first.');
      return;
    }
    setState(() => _testing = true);
    try {
      final library = await OpdsClient(settings).fetchLibrary();
      if (!mounted) return;
      _snack('Connected — found ${library.length} series.');
    } on OpdsException catch (e) {
      if (!mounted) return;
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _connectAndFinish() async {
    final settings = _currentSettings();
    if (!settings.isConfigured) {
      _snack('Enter a server address first.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _settingsService.save(settings);
      await _settingsService.markOnboardingSeen();
      if (!mounted) return;
      widget.onFinished();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() async {
    await _settingsService.markOnboardingSeen();
    if (!mounted) return;
    widget.onFinished();
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: isError ? 6 : 3),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to Umbra Reader',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect to your Novel Grabber library to start reading. '
                'The OPDS server runs on your computer over your local network.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Server address',
                  hintText: 'http://192.168.1.42:8765',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Password (optional)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing ? 'Testing…' : 'Test connection'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _connectAndFinish,
                child: Text(_saving ? 'Connecting…' : 'Connect'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _skip,
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
