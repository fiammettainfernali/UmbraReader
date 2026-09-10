// Keeping your place in something you read on someone else's website.
//
// The rules that matter here are the ones that protect a place already
// held: following a series twice must not reset it, re-reading an early
// chapter must not un-read two hundred later ones, and a site that answers
// oddly once must not retract chapters it has already offered.

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra_reader/db/app_database.dart';
import 'package:umbra_reader/services/web_series_metadata.dart';
import 'package:umbra_reader/services/web_series_store.dart';

import 'helpers/test_db.dart';

const _url = 'https://example.org/series/a-story-c6f3k3os';

WebSeriesInfo _info({String? title, String? cover, double? latest}) =>
    WebSeriesInfo(
      title: title,
      coverUrl: cover,
      latestChapterNumber: latest,
      latestChapterUrl: latest == null
          ? null
          : '$_url/chapter-${latest.round()}',
    );

void main() {
  late WebSeriesStore store;

  setUp(() async {
    await useInMemoryDatabase();
    store = WebSeriesStore();
  });

  tearDown(AppDatabase.reset);

  Future<WebSeries> get1() async => (await store.find(_url))!;

  test('following keeps what the page said about itself', () async {
    await store.follow(
      url: _url,
      title: 'fallback',
      info: _info(title: 'A Story', cover: 'https://cdn/x.webp', latest: 260),
    );
    final s = await get1();
    expect(s.title, 'A Story');
    expect(s.coverUrl, 'https://cdn/x.webp');
    expect(s.latestChapter, 260);
    // Nothing has been opened, so there is nowhere to return to but the
    // series page itself.
    expect(s.openUrl, _url);
    expect(s.isStarted, isFalse);
  });

  test(
    'the page title wins over the tab title, which wins over the URL',
    () async {
      await store.follow(url: _url, title: 'Tab Title | Example');
      expect((await get1()).title, 'Tab Title | Example');
      await store.follow(
        url: _url,
        title: 'Tab Title',
        info: _info(title: 'Real'),
      );
      expect((await get1()).title, 'Real');
    },
  );

  test('following again does not throw away where you were', () async {
    // The obvious way to lose two hundred chapters: tap follow on something
    // already followed.
    await store.follow(url: _url, title: 'A Story');
    await store.notePosition(
      seriesUrl: _url,
      chapterUrl: '$_url/chapter-212',
      panel: 31,
    );
    await store.follow(url: _url, title: 'A Story', info: _info(latest: 260));

    final s = await get1();
    expect(s.lastChapterUrl, '$_url/chapter-212');
    expect(s.lastPanel, 31);
    expect(s.readChapter, 212);
    expect(s.latestChapter, 260);
  });

  test('a position is a chapter and a panel', () async {
    await store.follow(url: _url, title: 'A Story');
    await store.notePosition(
      seriesUrl: _url,
      chapterUrl: '$_url/chapter-3',
      panel: 12,
    );
    final s = await get1();
    expect(s.lastPanel, 12);
    expect(s.openUrl, '$_url/chapter-3');
    expect(s.isStarted, isTrue);
    expect(s.openedAt, isNotNull);
  });

  test('re-reading an early chapter does not un-read the later ones', () async {
    await store.follow(url: _url, title: 'A Story', info: _info(latest: 260));
    await store.notePosition(seriesUrl: _url, chapterUrl: '$_url/chapter-212');
    await store.notePosition(seriesUrl: _url, chapterUrl: '$_url/chapter-3');

    final s = await get1();
    // Where you are now, but not a smaller idea of how far you have read.
    expect(s.openUrl, '$_url/chapter-3');
    expect(s.readChapter, 212);
    expect(s.unreadCount, 48);
  });

  test('an unknown panel leaves the saved one alone', () async {
    // "Not known right now" and "the top of the page" are different
    // answers, and the difference is the reader's place. The screen saves
    // on a timer, so it asks while a page is still loading its panels —
    // when the only answer available is 0.
    await store.follow(url: _url, title: 'A Story');
    await store.notePosition(
      seriesUrl: _url,
      chapterUrl: '$_url/chapter-9',
      panel: 31,
    );
    await store.notePosition(seriesUrl: _url, chapterUrl: '$_url/chapter-9');
    expect((await get1()).lastPanel, 31);

    // A real 0 still writes: scrolling back to the top is a position too.
    await store.notePosition(
      seriesUrl: _url,
      chapterUrl: '$_url/chapter-9',
      panel: 0,
    );
    expect((await get1()).lastPanel, 0);
  });

  test(
    'a chapter whose slug carries no number leaves the mark alone',
    () async {
      await store.follow(url: _url, title: 'A Story');
      await store.notePosition(seriesUrl: _url, chapterUrl: '$_url/chapter-40');
      await store.notePosition(seriesUrl: _url, chapterUrl: '$_url/epilogue');
      expect((await get1()).readChapter, 40);
    },
  );

  test('a check moves the latest chapter forward, never back', () async {
    await store.follow(url: _url, title: 'A Story', info: _info(latest: 260));
    await store.noteCheck(_url, _info(latest: 261));
    expect((await get1()).latestChapter, 261);

    // A page that rendered its list oddly must not un-announce a chapter.
    await store.noteCheck(_url, _info(latest: 4));
    expect((await get1()).latestChapter, 261);

    // Nor must one that could not be read at all.
    await store.noteCheck(_url, _info());
    expect((await get1()).latestChapter, 261);
  });

  test(
    'a check records when it happened, so staleness can be judged',
    () async {
      await store.follow(url: _url, title: 'A Story');
      expect((await get1()).checkedAt, isNull);
      await store.noteCheck(_url, _info(latest: 9));
      expect((await get1()).checkedAt, isNotNull);
    },
  );

  group('unread', () {
    test('a followed series never opened has something to read', () async {
      await store.follow(url: _url, title: 'A', info: _info(latest: 260));
      final s = await get1();
      expect(s.hasUnread, isTrue);
      // But not a number: the site's numbering is not a promise that every
      // integer below it exists.
      expect(s.unreadCount, isNull);
    });

    test('caught up is not unread', () async {
      await store.follow(url: _url, title: 'A', info: _info(latest: 260));
      await store.notePosition(
        seriesUrl: _url,
        chapterUrl: '$_url/chapter-260',
      );
      final s = await get1();
      expect(s.hasUnread, isFalse);
      expect(s.unreadCount, isNull);
    });

    test('a site that numbers nothing claims nothing', () async {
      await store.follow(url: _url, title: 'A');
      expect((await get1()).hasUnread, isFalse);
    });

    test('half a chapter still counts as one', () async {
      await store.follow(url: _url, title: 'A', info: _info(latest: 12));
      await store.notePosition(
        seriesUrl: _url,
        chapterUrl: '$_url/chapter-11.5',
      );
      final s = await get1();
      expect(s.hasUnread, isTrue);
      expect(s.unreadCount, 1);
    });
  });

  test('unfollowing forgets it', () async {
    await store.follow(url: _url, title: 'A Story');
    expect(await store.isFollowed(_url), isTrue);
    await store.unfollow(_url);
    expect(await store.isFollowed(_url), isFalse);
    expect(await store.find(_url), isNull);
  });

  test('writes for a series that is not followed do nothing', () async {
    // The screen saves on a timer; unfollowing while it is open must not
    // resurrect the row.
    await store.notePosition(seriesUrl: _url, chapterUrl: '$_url/chapter-1');
    await store.noteCheck(_url, _info(latest: 5));
    expect(await store.find(_url), isNull);
  });

  test('the shelf is ordered by what you last opened', () async {
    await store.follow(url: '$_url-a', title: 'A');
    await store.follow(url: '$_url-b', title: 'B');
    await store.follow(url: '$_url-c', title: 'C');
    await store.notePosition(
      seriesUrl: '$_url-a',
      chapterUrl: '$_url-a/chapter-1',
    );

    final all = await store.all();
    expect(all.first.title, 'A', reason: 'the one just read should lead');
    expect(all.length, 3);
  });
}
