import 'package:flutter/material.dart';

import '../services/pro_service.dart';

/// Returns true when the user holds Umbra Pro; otherwise shows the upsell
/// sheet and returns false. Every gated feature funnels through this.
Future<bool> requirePro(BuildContext context, {required String feature}) async {
  if (ProService().isPro.value) return true;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ProSheet(highlightedFeature: feature),
  );
  // Purchasing inside the sheet flips the notifier; re-check on return.
  return ProService().isPro.value;
}

/// The Umbra Pro upsell: what's included, and (once the store flow lands)
/// the unlock button. Until then the button explains itself honestly.
class ProSheet extends StatelessWidget {
  const ProSheet({super.key, required this.highlightedFeature});

  /// The feature the user just tapped — listed first so the sheet answers
  /// "why am I seeing this?".
  final String highlightedFeature;

  static const _features = <(IconData, String)>[
    (Icons.palette_outlined, 'Custom reading themes'),
    (Icons.manage_search, 'Search inside every book'),
    (Icons.local_fire_department_outlined, 'Reading stats, goals & streaks'),
    (Icons.notes_outlined, 'Export annotations as Markdown'),
    (Icons.cloud_outlined, 'iCloud sync across devices'),
    (Icons.collections_bookmark_outlined, 'Collections'),
    (Icons.tv_outlined, 'TV & spread reading mode'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [
      ..._features.where((f) => f.$2 == highlightedFeature),
      ..._features.where((f) => f.$2 != highlightedFeature),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.tertiary),
                const SizedBox(width: 10),
                Text(
                  'Umbra Pro',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'One purchase, yours forever. Everything you need to read is '
              'free — Pro is for living in your library.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final (icon, label) in ordered)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: label == highlightedFeature
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: label == highlightedFeature
                            ? theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              )
                            : theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                // The StoreKit flow is the next slice; until it lands this
                // build simply doesn't sell — no dead-looking buy button.
                onPressed: null,
                child: const Text('Coming soon to the App Store'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
