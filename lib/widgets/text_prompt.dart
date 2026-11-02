// Asking for one line of text, without the caller owning the controller.
//
// The obvious way to write this crashes, and did — on Add by URL, with
// "'_dependents.isEmpty': is not true" and a red screen:
//
//     final controller = TextEditingController();
//     final text = await showDialog(... controller ...);
//     controller.dispose();          // too early
//
// showDialog's future completes when the route is *popped*, not when it is
// gone. The dialog is still on screen playing its exit animation, and the
// TextField in it is still mounted, still painting, and still listening to
// that controller — so disposing it there tears down something the framework
// is in the middle of using.
//
// A widget that owns its controller has no such problem: the framework
// disposes it after the animation, which is the only moment that is
// actually safe. reader_screen's note sheet already worked this out once;
// this is the same answer, in a form the other six callers can share.

import 'package:flutter/material.dart';

/// Asks for a line of text. Returns it trimmed, or null if cancelled.
///
/// Empty input comes back as null too: every caller treated "" as "changed
/// their mind", and saying so once here is better than six of them
/// remembering to.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? helper,
  String confirmLabel = 'Save',
  TextInputType? keyboardType,
  bool autocorrect = true,
  int minLines = 1,
  int maxLines = 1,
}) async {
  final text = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _TextPromptDialog(
      title: title,
      initial: initial,
      hint: hint,
      helper: helper,
      confirmLabel: confirmLabel,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      minLines: minLines,
      maxLines: maxLines,
    ),
  );
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.helper,
    required this.confirmLabel,
    required this.keyboardType,
    required this.autocorrect,
    required this.minLines,
    required this.maxLines,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? helper;
  final String confirmLabel;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final int minLines;
  final int maxLines;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    // The whole point. Reached only once the dialog has finished closing.
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: widget.autocorrect,
        keyboardType: widget.keyboardType,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        // A one-line prompt is a sentence you finish with the keyboard, not
        // one you reach across the screen to confirm.
        textInputAction: widget.maxLines == 1 ? TextInputAction.done : null,
        onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
        decoration: InputDecoration(
          hintText: widget.hint,
          helperText: widget.helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
