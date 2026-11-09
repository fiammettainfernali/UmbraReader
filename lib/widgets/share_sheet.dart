import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/browser_policy.dart';
import '../services/control_client.dart';
import '../services/novel_send_queue.dart';
import '../services/settings_service.dart';
import '../services/shared_link.dart';

/// Back to the app the link was shared from. Silent on failure: all that's lost
/// is the shortcut, and the sheet has already said how it went.
Future<void> leaveToPreviousApp() async {
  try {
    await const MethodChannel('umbra/share').invokeMethod<bool>('leave');
  } on PlatformException {
    // Stay here.
  } on MissingPluginException {
    // Not on Android.
  }
}

/// Shows what became of a link shared from another app.
///
/// A novel's page goes straight to the computer: choosing this app in the share
/// menu already was the decision. Anything else asks first, since it's most
/// likely a link to the wrong page.
Future<void> showShareSheet(
  BuildContext context,
  SharedLink link,
  OpdsSettings settings,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ShareSheet(link: link, settings: settings),
  );
}

enum _Stage {
  asking,
  sending,
  sent,
  waiting,
  duplicate,
  failed,
  notSetUp,
  noLink,
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.link, required this.settings});

  final SharedLink link;
  final OpdsSettings settings;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  static const _sentPause = Duration(milliseconds: 1500);
  static const _waitingPause = Duration(seconds: 4);

  late final ControlClient _client = ControlClient(widget.settings);
  _Stage _stage = _Stage.sending;
  String? _note;
  Timer? _leaving;

  @override
  void initState() {
    super.initState();
    if (widget.link.kind == SharedKind.noLink) {
      _stage = _Stage.noLink;
    } else if (!widget.settings.isConfigured) {
      _stage = _Stage.notSetUp;
    } else if (widget.link.kind == SharedKind.novel) {
      unawaited(_send());
    } else {
      _stage = _Stage.asking;
    }
  }

  @override
  void dispose() {
    _leaving?.cancel();
    super.dispose();
  }

  Future<void> _send({bool force = false}) async {
    // It's already showing this when the sheet opens by sending straight away.
    if (_stage != _Stage.sending) setState(() => _stage = _Stage.sending);
    final result = await sendNovelToComputer(
      _client,
      widget.link.url!,
      widget.link.label,
      force: force,
    );
    if (!mounted) return;
    setState(() {
      _note = result.note;
      _stage = switch (result.state) {
        SendState.sent => _Stage.sent,
        SendState.waiting => _Stage.waiting,
        SendState.duplicate => _Stage.duplicate,
        _ => _Stage.failed,
      };
    });
    if (_stage == _Stage.sent) _finishAfter(_sentPause);
    if (_stage == _Stage.waiting) _finishAfter(_waitingPause);
  }

  void _finishAfter(Duration pause) {
    _leaving = Timer(pause, _finish);
  }

  /// Done here, so back to whatever they were looking at.
  void _finish() {
    _leaving?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
    unawaited(leaveToPreviousApp());
  }

  Future<void> _remove() async {
    _leaving?.cancel();
    await forgetWaitingNovel(widget.link.url!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String get _heading => switch (_stage) {
    _Stage.asking => 'Send this page anyway?',
    _Stage.sending => 'Sending to your computer',
    _Stage.sent => 'Sent to your computer',
    _Stage.waiting => 'Saved for later',
    _Stage.duplicate => 'Already have this?',
    _Stage.failed => 'That didn\'t send',
    _Stage.notSetUp => 'Your computer isn\'t set up yet',
    _Stage.noLink => 'There\'s no link in that',
  };

  String? get _detail => switch (_stage) {
    _Stage.asking =>
      widget.link.kind == SharedKind.unsupportedSite
          ? 'Your computer can\'t usually get novels from '
                '${_host ?? 'this site'}.'
          : 'This doesn\'t look like a novel\'s own page.',
    _Stage.sending => null,
    _Stage.sent => null,
    _Stage.waiting => 'Can\'t reach your computer. It goes when it\'s back.',
    _Stage.duplicate => _note,
    _Stage.failed => _note,
    _Stage.notSetUp =>
      'Connect to it from the Server tab, then share the link again.',
    _Stage.noLink => 'Only a web address can be sent to your computer.',
  };

  String? get _host {
    final url = Uri.tryParse(widget.link.url ?? '');
    return url == null ? null : displayHost(url);
  }

  IconData get _icon => switch (_stage) {
    _Stage.sent => Icons.check_circle,
    _Stage.waiting => Icons.schedule,
    _Stage.duplicate => Icons.library_add_check,
    _Stage.failed => Icons.error_outline,
    _Stage.notSetUp => Icons.computer,
    _ => Icons.help_outline,
  };

  List<Widget> _buttons() {
    Widget done(String label) =>
        OutlinedButton(onPressed: _finish, child: Text(label));
    return switch (_stage) {
      _Stage.asking => [
        OutlinedButton(onPressed: _finish, child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: () => unawaited(_send()),
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Send anyway'),
        ),
      ],
      _Stage.sending || _Stage.sent => const [],
      _Stage.waiting => [
        OutlinedButton(
          onPressed: () => unawaited(_remove()),
          child: const Text('Remove'),
        ),
        done('Done'),
      ],
      _Stage.duplicate => [
        done('Leave it'),
        FilledButton(
          onPressed: () => unawaited(_send(force: true)),
          child: const Text('Add anyway'),
        ),
      ],
      _Stage.failed => [
        done('Close'),
        FilledButton(
          onPressed: () => unawaited(_send()),
          child: const Text('Try again'),
        ),
      ],
      _Stage.notSetUp || _Stage.noLink => [done('Close')],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = _detail;
    final buttons = _buttons();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: _stage == _Stage.sending
                      ? const Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(_icon, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_heading, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            if (widget.link.label.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.link.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (buttons.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final (index, button) in buttons.indexed) ...[
                    if (index > 0) const SizedBox(width: 10),
                    Expanded(child: button),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
