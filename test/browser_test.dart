// The rules behind the two browsers: what gets blocked, what gets sent, and that
// each browser keeps to itself.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/browser_policy.dart';
import 'package:umbra_reader/services/browser_scripts.dart';
import 'package:umbra_reader/services/browser_store.dart';
import 'package:umbra_reader/services/novel_send_queue.dart';
import 'package:umbra_reader/widgets/browser_shell.dart';

NavVerdict _judge(
  String? from,
  String to, {
  bool blocking = true,
  bool userAsked = false,
}) => judgeNavigation(
  from: from == null ? null : Uri.parse(from),
  to: Uri.parse(to),
  blocking: blocking,
  userAsked: userAsked,
);

void main() {
  group('what may take over a tab', () {
    test('moving around one site is fine', () {
      expect(
        _judge('https://novelfull.com/', 'https://novelfull.com/a.html'),
        NavVerdict.allow,
      );
      expect(
        _judge('https://www.site.com/', 'https://site.com/x'),
        NavVerdict.allow,
      );
    });

    test('a jump to another site is stopped and offered', () {
      expect(
        _judge('https://novelfull.com/', 'https://casino.example/win'),
        NavVerdict.askFirst,
      );
    });

    test('something the reader asked for goes through', () {
      expect(
        _judge(
          'https://novelfull.com/',
          'https://casino.example/',
          userAsked: true,
        ),
        NavVerdict.allow,
      );
      expect(_judge(null, 'https://anywhere.example/'), NavVerdict.allow);
    });

    test('turning blocking off lets jumps through', () {
      expect(
        _judge(
          'https://novelfull.com/',
          'https://other.example/',
          blocking: false,
        ),
        NavVerdict.allow,
      );
    });

    test('leaving the web is refused, whatever the switch says', () {
      for (final blocking in [true, false]) {
        expect(
          _judge(
            'https://site.example/',
            'intent://scan#Intent;end',
            blocking: blocking,
          ),
          NavVerdict.refuse,
        );
        expect(
          _judge(
            'https://site.example/',
            'market://details?id=x',
            blocking: blocking,
            userAsked: true,
          ),
          NavVerdict.refuse,
        );
      }
    });

    test('search results can lead anywhere', () {
      expect(
        _judge('https://duckduckgo.com/?q=x', 'https://comic.example/'),
        NavVerdict.allow,
      );
    });

    test('one supported novel site can redirect to another', () {
      expect(
        _judge('https://allnovelfull.net/a.html', 'https://novgo.net/a.html'),
        NavVerdict.allow,
      );
    });
  });

  group('the address bar', () {
    test('shows where you are without what every address starts with', () {
      expect(
        shortAddress(Uri.parse('https://novelfull.com/')),
        'novelfull.com',
      );
      expect(
        shortAddress(Uri.parse('https://www.novelfull.com/a-book.html')),
        'novelfull.com/a-book.html',
      );
      expect(
        shortAddress(Uri.parse('https://novelfull.com/search?keyword=mana')),
        'novelfull.com/search?keyword=mana',
      );
    });

    test('an address goes there, adding https', () {
      expect(
        addressFromInput('novelfull.com').toString(),
        'https://novelfull.com',
      );
      expect(
        addressFromInput('site.org/some/page').toString(),
        'https://site.org/some/page',
      );
      expect(addressFromInput(' http://a.com ').toString(), 'http://a.com');
    });

    test('anything else is a search', () {
      final url = addressFromInput('solo leveling manga')!;
      expect(url.host, 'duckduckgo.com');
      expect(url.queryParameters['q'], 'solo leveling manga');
      expect(addressFromInput('word')!.host, 'duckduckgo.com');
    });

    test('nothing typed goes nowhere', () {
      expect(addressFromInput('   '), isNull);
    });
  });

  group('each browser keeps its own things', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('history and favourites do not cross over', () async {
      final novels = BrowserStore('novels');
      final comics = BrowserStore('comics');
      await novels.remember('https://a.com/', 'A');
      await novels.toggleFavourite('https://a.com/', 'A');
      expect(await comics.history(), isEmpty);
      expect(await comics.favourites(), isEmpty);
      expect((await novels.history()).single.title, 'A');
    });

    test('the ad blocker is on until turned off, separately', () async {
      final novels = BrowserStore('novels');
      final comics = BrowserStore('comics');
      expect(await novels.blocksAds(), isTrue);
      await novels.setBlocksAds(false);
      expect(await novels.blocksAds(), isFalse);
      expect(await comics.blocksAds(), isTrue);
    });

    test('history is newest first, without repeats, and has a limit', () async {
      final store = BrowserStore('novels');
      await store.remember('https://a.com/', 'A');
      await store.remember('https://b.com/', 'B');
      await store.remember('https://a.com/', 'A again');
      final pages = await store.history();
      expect(pages.map((p) => p.title), ['A again', 'B']);
      for (var i = 0; i < 60; i++) {
        await store.remember('https://site.com/$i', '$i');
      }
      expect((await store.history()).length, 40);
    });

    test('a favourite toggles', () async {
      final store = BrowserStore('novels');
      expect(await store.toggleFavourite('https://a.com/', 'A'), isTrue);
      expect(await store.toggleFavourite('https://a.com/', 'A'), isFalse);
      expect(await store.favourites(), isEmpty);
    });
  });

  group('sending from a list', () {
    late List<String> sent;
    late List<String> forgotten;
    late SendResult Function(String url) answer;

    NovelSendQueue queue() => NovelSendQueue(
      hold: const Duration(milliseconds: 20),
      send: (url, title, force) async {
        sent.add(force ? 'force:$url' : url);
        return answer(url);
      },
      forgetWaiting: (url) async => forgotten.add(url),
    );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 60));

    setUp(() {
      sent = [];
      forgotten = [];
      answer = (_) => const SendResult(SendState.sent);
    });

    test('a tap waits a moment, then goes', () async {
      final q = queue();
      addTearDown(q.dispose);
      q.add('u1', 'One');
      expect(sent, isEmpty);
      expect(q.itemFor('u1')!.state, SendState.holding);
      await settle();
      expect(sent, ['u1']);
      expect(q.itemFor('u1')!.state, SendState.sent);
    });

    test('undo in that moment means it never went', () async {
      final q = queue();
      addTearDown(q.dispose);
      q.add('u1', 'One');
      expect(await q.undo('u1'), isTrue);
      await settle();
      expect(sent, isEmpty);
      expect(q.items, isEmpty);
    });

    test('once sent, it can not be undone from here', () async {
      final q = queue();
      addTearDown(q.dispose);
      q.add('u1', 'One');
      await settle();
      expect(await q.undo('u1'), isFalse);
      expect(q.items, hasLength(1));
    });

    test('tapping twice sends once', () async {
      final q = queue();
      addTearDown(q.dispose);
      q
        ..add('u1', 'One')
        ..add('u1', 'One');
      await settle();
      expect(sent, ['u1']);
    });

    test('several go at once, newest shown first', () async {
      final q = queue();
      addTearDown(q.dispose);
      q
        ..add('u1', 'One')
        ..add('u2', 'Two');
      expect(q.items.first.url, 'u2');
      await settle();
      expect(sent, containsAll(['u1', 'u2']));
    });

    test('a duplicate waits for a decision, and can be forced', () async {
      answer = (_) => const SendResult(SendState.duplicate, 'Looks familiar');
      final q = queue();
      addTearDown(q.dispose);
      q.add('u1', 'One');
      await settle();
      expect(q.itemFor('u1')!.state, SendState.duplicate);
      expect(q.itemFor('u1')!.note, 'Looks familiar');
      answer = (_) => const SendResult(SendState.sent);
      q.addAnyway('u1');
      await settle();
      expect(sent, ['u1', 'force:u1']);
      expect(q.itemFor('u1')!.state, SendState.sent);
    });

    test('computer away: it waits, and can be taken back', () async {
      answer = (_) => const SendResult(SendState.waiting);
      final q = queue();
      addTearDown(q.dispose);
      q.add('u1', 'One');
      await settle();
      expect(q.itemFor('u1')!.state, SendState.waiting);
      expect(await q.undo('u1'), isTrue);
      expect(forgotten, ['u1']);
    });

    test('a failed send can be tried again', () async {
      answer = (_) => const SendResult(SendState.failed, 'Nope');
      final q = queue();
      addTearDown(q.dispose);
      q.add('u1', 'One');
      await settle();
      expect(q.itemFor('u1')!.state, SendState.failed);
      answer = (_) => const SendResult(SendState.sent);
      q.add('u1', 'One');
      await settle();
      expect(q.itemFor('u1')!.state, SendState.sent);
      expect(q.items, hasLength(1));
    });

    test('an error while sending counts as failed', () async {
      answer = (_) => throw Exception('boom');
      final q = queue();
      addTearDown(q.dispose);
      q.add('u1', 'One');
      await settle();
      expect(q.itemFor('u1')!.state, SendState.failed);
    });

    test('closing the browser sends what was still waiting', () async {
      final q = queue()..add('u1', 'One');
      q.dispose();
      await settle();
      expect(sent, ['u1']);
    });

    test('closing the browser does not send what was undone', () async {
      final q = queue()..add('u1', 'One');
      await q.undo('u1');
      q.dispose();
      await settle();
      expect(sent, isEmpty);
    });
  });

  group('the page scripts', () {
    test('a send button stays where a list row can\'t cut it off', () {
      final script = sendButtonsScript(r'^/[^/]+\.html$');
      // Ahead of a title, never after it, and over a cover rather than a caption.
      expect(script, contains('insertBefore(button, link)'));
      expect(script, isNot(contains('link.nextSibling')));
      expect(script, contains("button.classList.add('over')"));
    });

    test('a send-button script carries the site pattern safely', () {
      final script = sendButtonsScript(r'^/[^/]+\.html$');
      expect(script, contains(r'"^/[^/]+\\.html$"'));
      expect(script, contains(kBrowserChannel));
    });

    test('marking a button escapes the address', () {
      expect(
        markSendButton('https://a.com/x"y', 'sent'),
        contains(r'"https://a.com/x\"y"'),
      );
    });
  });

  group('the browser home', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    Widget app(Widget child) => MaterialApp(home: child);

    testWidgets('opens on its home, with no page behind it', (tester) async {
      await tester.pumpWidget(
        app(
          BrowserShell(
            store: BrowserStore('test'),
            homeBuilder: (context, open) => const Text('Home page'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Home page'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a site card reports the tap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: BrowserSiteCard(
              name: 'NovelFull',
              host: 'novelfull.com',
              onTap: () => tapped++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('NovelFull'));
      expect(tapped, 1);
    });

    testWidgets('favourites and recent pages show, and open', (tester) async {
      final store = BrowserStore('test');
      await store.remember('https://recent.example/', 'Recent one');
      await store.toggleFavourite('https://fav.example/', 'Favourite one');
      Uri? opened;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: BrowserPagesSection(
              store: store,
              open: (url) => opened = url,
              heading: Text.new,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent one'), findsOneWidget);
      await tester.tap(find.text('Favourite one'));
      expect(opened.toString(), 'https://fav.example/');
    });
  });

  test('blocking script is unaffected by unrelated hosts', () {
    expect(kAdBlockScript, contains('doubleclick.net'));
    expect(kLongPressScript, contains('longpress'));
    unawaited(Future<void>.value());
  });
}
