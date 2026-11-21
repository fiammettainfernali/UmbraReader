import 'package:flutter/material.dart';

/// Five stars to tap. Tapping the stars already given clears them.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.stars,
    required this.onRate,
    this.size = 30,
  });

  final int stars;
  final ValueChanged<int> onRate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: i == stars
                ? 'Clear the rating'
                : '$i star${i == 1 ? '' : 's'}',
            visualDensity: VisualDensity.compact,
            iconSize: size,
            onPressed: () => onRate(i == stars ? 0 : i),
            icon: Icon(
              i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i <= stars ? color : null,
            ),
          ),
      ],
    );
  }
}

/// A small read-only line of stars, for a card or a list.
class StarsLabel extends StatelessWidget {
  const StarsLabel(this.stars, {super.key, this.size = 14});

  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '$stars of 5 stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i <= stars ? color : color.withValues(alpha: 0.35),
            ),
        ],
      ),
    );
  }
}
