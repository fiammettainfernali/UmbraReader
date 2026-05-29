import 'package:flutter/material.dart';

import '../services/opds_client.dart';
import '../services/settings_service.dart';

/// Lets the user enter and save the Novel Grabber OPDS server connection.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.initial});

  final OpdsSettings initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsService = SettingsService();
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool _testing = false;
  bool _obscurePassword = true;

  bool _autoDownload = true;
  bool _autoDownloadWifiOnly = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initial.baseUrl);
    _usernameController = TextEditingController(text: widget.initial.username);
    _passwordController = TextEditingController(text: widget.initial.password);
    _loadDownloadPrefs();
  }

  Future<void> _loadDownloadPrefs() async {
    final auto = await _settingsService.autoDownloadNext();
    final wifi = await _settingsService.autoDownloadWifiOnly();
    if (!mounted) return;
    setState(() {
      _autoDownload = auto;
      _autoDownloadWifiOnly = wifi;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Builds an [OpdsSettings] from the current field values.
  OpdsSettings _currentSettings() {
    return OpdsSettings(
      baseUrl: normalizeOpdsUrl(_urlController.text),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  Future<void> _save() async {
    final settings = _currentSettings();
    await _settingsService.save(settings);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _testConnection() async {
    final settings = _currentSettings();
    if (!settings.isConfigured) {
      _showSnack('Enter a server address first.');
      return;
    }
    setState(() => _testing = true);
    try {
      final library = await OpdsClient(settings).fetchLibrary();
      if (!mounted) return;
      _showSnack('Connected — found ${library.length} series.');
    } on OpdsException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server settings'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Connect to your Novel Grabber library',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'In Novel Grabber, start the OPDS server and copy the LAN address '
            'it shows (something like http://192.168.1.42:8765).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
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
              helperText: 'Only if you set up authentication in Novel Grabber',
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
          const SizedBox(height: 24),
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
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Downloads',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-download next volume'),
            subtitle: const Text(
              'Keep the next volume of books you\'re reading ready offline, '
              'so it\'s already there when you finish one.',
            ),
            value: _autoDownload,
            onChanged: (value) {
              setState(() => _autoDownload = value);
              _settingsService.setAutoDownloadNext(value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wi-Fi only'),
            subtitle: const Text(
              'Only auto-download on Wi-Fi, never on cellular data.',
            ),
            value: _autoDownloadWifiOnly,
            onChanged: _autoDownload
                ? (value) {
                    setState(() => _autoDownloadWifiOnly = value);
                    _settingsService.setAutoDownloadWifiOnly(value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
