import 'package:flutter/material.dart';

/// A skip-back / skip-forward button (circular arrow + the number of seconds),
/// styled like the iOS audiobook transport. Used in the Listen player and the
/// in-reader read-aloud transport.
class SeekButton extends StatelessWidget {
  const SeekButton({
    super.key,
    required this.seconds,
    required this.color,
    required this.onTap,
    this.size = 40,
  });

  /// Negative for back, positive for forward.
  final int seconds;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: seconds < 0
          ? 'Back ${seconds.abs()} seconds'
          : 'Forward $seconds seconds',
      onPressed: onTap,
      icon: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Mirror the circular-arrow icon for the forward direction.
            Transform.scale(
              scaleX: seconds < 0 ? 1 : -1,
              child: Icon(Icons.replay, size: size - 2, color: color),
            ),
            Text(
              '${seconds.abs()}',
              style: TextStyle(
                color: color,
                fontSize: size * 0.29,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
