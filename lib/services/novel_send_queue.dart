import 'dart:async';

import 'package:flutter/foundation.dart';

import 'control_client.dart';
import 'pending_add_store.dart';

/// Asks the computer to add a novel. When it's out of reach the novel is saved to
/// go when it's back, so this only reports a failure the computer itself gave.
Future<SendResult> sendNovelToComputer(
  ControlClient client,
  String url,
  String title, {
  bool force = false,
}) async {
  try {
    await client.addNovel(url, force: force);
    return const SendResult(SendState.sent, 'Sent to your computer');
  } on DuplicateNovelException catch (e) {
    final match = e.matches.isEmpty ? null : e.matches.first;
    return SendResult(
      SendState.duplicate,
      e.isSameUrl
          ? 'Already in your library'
          : 'Looks like ${match?.title ?? 'something you already have'}',
    );
  } on ControlException catch (e) {
    if (!e.isUnreachable) return SendResult(SendState.failed, e.message);
    await PendingAddStore().enqueue(url, label: title, force: force);
    return const SendResult(
      SendState.waiting,
      'Goes when your computer is back',
    );
  }
}

/// Takes back a novel saved for when the computer returns.
Future<void> forgetWaitingNovel(String url) async {
  final store = PendingAddStore();
  for (final pending in await store.list()) {
    if (pending.url == url) await store.remove(pending.id);
  }
}

/// Where a novel sent from the browser has got to.
enum SendState {
  /// Tapped, and waiting a moment so a mistake can be undone.
  holding,
  sending,
  sent,

  /// The computer was out of reach, so it goes when the app next connects.
  waiting,

  /// Looks like something already in the library. Waiting on a decision.
  duplicate,
  failed,
}

/// What came of asking the computer to add a novel.
class SendResult {
  const SendResult(this.state, [this.note]);

  final SendState state;
  final String? note;
}

class SendItem {
  SendItem({required this.url, required this.title});

  final String url;
  final String title;
  SendState state = SendState.holding;
  String? note;
}

/// The novels sent from the browser's lists, without leaving the list.
///
/// A tap holds for a moment before anything goes to the computer, because a
/// computer that has started on a novel can't be asked to forget it from here.
/// Those few seconds are what make Undo mean what it says.
///
/// Nothing here interrupts. A duplicate waits in the list for a decision rather
/// than stopping someone part-way down a page with a dialog.
class NovelSendQueue extends ChangeNotifier {
  NovelSendQueue({
    required this.send,
    required this.forgetWaiting,
    this.hold = const Duration(seconds: 4),
  });

  final Future<SendResult> Function(String url, String title, bool force) send;

  /// Takes back something saved for when the computer returns.
  final Future<void> Function(String url) forgetWaiting;
  final Duration hold;

  final List<SendItem> _items = [];
  final Map<String, Timer> _timers = {};
  bool _disposed = false;

  List<SendItem> get items => List.unmodifiable(_items);

  SendItem? itemFor(String url) {
    for (final item in _items) {
      if (item.url == url) return item;
    }
    return null;
  }

  int countOf(SendState state) => _items.where((i) => i.state == state).length;

  /// Adds a novel. Tapping one already on its way does nothing, while one that
  /// failed gets another go.
  void add(String url, String title) {
    final existing = itemFor(url);
    if (existing != null && existing.state != SendState.failed) return;
    final item = existing ?? SendItem(url: url, title: title);
    item
      ..state = SendState.holding
      ..note = null;
    if (existing == null) _items.insert(0, item);
    _timers[url] = Timer(hold, () => _go(item, force: false));
    _changed();
  }

  /// Takes a novel back, while that's still possible. Returns whether it was.
  Future<bool> undo(String url) async {
    final item = itemFor(url);
    if (item == null) return false;
    switch (item.state) {
      case SendState.holding:
        _timers.remove(url)?.cancel();
      case SendState.waiting:
        await forgetWaiting(url);
      case SendState.duplicate:
      case SendState.failed:
        break;
      case SendState.sending:
      case SendState.sent:
        return false;
    }
    _items.remove(item);
    _changed();
    return true;
  }

  /// The answer to a duplicate: yes, add it anyway.
  void addAnyway(String url) {
    final item = itemFor(url);
    if (item != null) unawaited(_go(item, force: true));
  }

  /// Sends everything still holding, for when the browser closes.
  void flush() {
    for (final item in _items) {
      if (item.state == SendState.holding) {
        _timers.remove(item.url)?.cancel();
        unawaited(_go(item, force: false));
      }
    }
  }

  Future<void> _go(SendItem item, {required bool force}) async {
    _timers.remove(item.url);
    item
      ..state = SendState.sending
      ..note = null;
    _changed();
    SendResult result;
    try {
      result = await send(item.url, item.title, force);
    } on Exception catch (e) {
      result = SendResult(SendState.failed, '$e');
    }
    item
      ..state = result.state
      ..note = result.note;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    flush();
    _disposed = true;
    super.dispose();
  }
}
