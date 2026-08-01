import 'package:flutter/material.dart';

/// One row inside a popup menu: an icon and a label.
///
/// The app previously rendered menu items three different ways — this pattern
/// in the reader, a zero-padded `ListTile` in most screens, and bare `Text`
/// with no icon at all in Collections. Same control, three appearances. This
/// is the one to use.
///
/// Carries an explicit semantics label so a screen reader announces the row
/// rather than reading an icon and a string separately.
class MenuRow extends StatelessWidget {
  const MenuRow(this.icon, this.label, {super.key, this.isDestructive = false});

  final IconData icon;
  final String label;

  /// Tints the row with the error colour — for actions that remove something.
  /// Used sparingly: a red row is a warning, and most menu items are not.
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colour = isDestructive ? Theme.of(context).colorScheme.error : null;
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: colour),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: colour)),
        ],
      ),
    );
  }
}
