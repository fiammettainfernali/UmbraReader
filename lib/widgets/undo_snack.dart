import 'package:flutter/material.dart';

/// Confirms a destructive edit and offers to put it back.
///
/// Umbra guards deletions with undo rather than a confirmation dialog. A
/// confirm interrupts every time, including the many times the tap was
/// intended; an undo costs nothing when the action was wanted and still
/// rescues the mis-tap. It also matches the tone the rest of the app takes —
/// the reminders and streak grace never nag, and a modal asking "are you
/// sure?" about a highlight would.
///
/// [message] should name what went, in the past tense ("Highlight deleted").
void showUndoSnackBar(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        // Long enough to notice and reach, short enough not to linger.
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
}
