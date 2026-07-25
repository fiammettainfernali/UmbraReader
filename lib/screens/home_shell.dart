import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'library_screen.dart';
import 'manage_screen.dart';
import 'notes_screen.dart';
import 'stats_screen.dart';

/// The app's root: four destinations behind a bottom bar.
///
/// Everything that wasn't a book used to live in one "More" overflow menu on
/// the library — seven unrelated items mixing content, insight, maintenance
/// and configuration, so finding anything meant reading all seven. This gives
/// the app a spine, and in doing so gives annotations a home of their own
/// (they were previously reachable only from inside a book) and puts adding a
/// book one tap away instead of three.
///
/// Configuration and maintenance — settings, storage, backup, imported books —
/// deliberately stay *off* the bar: they are things you adjust, not places you
/// go, and they remain in the library's menu.
///
/// The reader is pushed over this shell rather than living in a tab, so
/// reading stays full-screen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  OpdsSettings? _settings;

  @override
  void initState() {
    super.initState();
    SettingsService().load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      // IndexedStack keeps each tab alive, so switching away and back doesn't
      // rebuild the library or lose a scroll position — which would read as
      // the app moving under you.
      body: IndexedStack(
        index: _index,
        children: [
          const LibraryScreen(),
          settings == null
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : ManageScreen(settings: settings),
          const NotesScreen(),
          const StatsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'You',
          ),
        ],
      ),
    );
  }
}
