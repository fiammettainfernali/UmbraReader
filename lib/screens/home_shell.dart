import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../widgets/glass_nav_bar.dart';
import 'library_screen.dart';
import 'manage_screen.dart';
import 'discover_screen.dart';
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
/// The four are deliberately different jobs. Library is the collection and
/// where reading resumes. Discover answers "what should I read" — the
/// shelves and every kind of search. Server answers "what is the machine
/// doing", which is a question about the downloader, not about books, and
/// used to hide behind a tab labelled Discover. You is reading history,
/// including the notes and highlights that were once a tab of their own.
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
    final mq = MediaQuery.of(context);
    // Android has a system back; iOS does not, so nothing here ever needed
    // to answer it. Back on a sub-tab belongs to the tab strip, not the app:
    // it returns to Library, and only a back from Library itself leaves.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _index = 0);
      },
      child: Scaffold(
        // The bar is glass, so the tabs have to scroll underneath it — with
        // nothing passing behind it there is nothing to blur.
        extendBody: true,
        body: MediaQuery(
          // Hand the tabs the bar's full footprint as bottom padding. They paint
          // beneath it now, so their lists and floating buttons need to know to
          // clear it; each tab reads this back as `padding.bottom`.
          data: mq.copyWith(
            padding: mq.padding.copyWith(
              bottom: mq.padding.bottom + GlassNavBar.barHeight,
            ),
          ),
          // IndexedStack keeps each tab alive, so switching away and back doesn't
          // rebuild the library or lose a scroll position — which would read as
          // the app moving under you.
          child: IndexedStack(
            index: _index,
            children: [
              const LibraryScreen(),
              // Both of these need the server address, so they wait on the
              // same settings load rather than each guessing at it.
              if (settings == null) ...[
                const Scaffold(body: Center(child: CircularProgressIndicator())),
                const Scaffold(body: Center(child: CircularProgressIndicator())),
              ] else ...[
                DiscoverScreen(settings: settings),
                ManageScreen(settings: settings),
              ],
              const StatsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: GlassNavBar(
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
              icon: Icon(Icons.dns_outlined),
              selectedIcon: Icon(Icons.dns),
              label: 'Server',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'You',
            ),
          ],
        ),
      ),
    );
  }
}
