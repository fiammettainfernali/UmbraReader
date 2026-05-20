import 'package:flutter/material.dart';

import 'screens/library_screen.dart';

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
      home: const LibraryScreen(),
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
