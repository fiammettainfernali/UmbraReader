import 'package:flutter/material.dart';

import '../models/reader_settings.dart';
import '../models/reader_theme.dart';

/// Font choices offered in the reader. An empty string is the system font.
const List<String> kReaderFonts = [
  '',
  'Literata',
  'Lora',
  'Atkinson Hyperlegible',
];

String _fontLabel(String family) => family.isEmpty ? 'System' : family;

/// Bottom sheet for adjusting reader settings live: layout mode, colour
/// theme, font, text size, line spacing and margins.
class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final ReaderSettings initial;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
  }

  void _update(ReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(theme, 'Layout'),
            SegmentedButton<ReadingMode>(
              segments: const [
                ButtonSegment(
                  value: ReadingMode.scroll,
                  label: Text('Scroll'),
                  icon: Icon(Icons.swap_vert),
                ),
                ButtonSegment(
                  value: ReadingMode.paged,
                  label: Text('Paged'),
                  icon: Icon(Icons.auto_stories),
                ),
              ],
              selected: {_settings.mode},
              onSelectionChanged: (selection) =>
                  _update(_settings.copyWith(mode: selection.first)),
            ),
            const SizedBox(height: 20),

            _label(theme, 'Theme'),
            Row(
              children: [
                for (final preset in kReaderThemes)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _ThemeSwatch(
                      preset: preset,
                      selected: preset.id == _settings.themeId,
                      onTap: () =>
                          _update(_settings.copyWith(themeId: preset.id)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            _label(theme, 'Font'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final font in kReaderFonts)
                  ChoiceChip(
                    label: Text(_fontLabel(font)),
                    selected: font == _settings.fontFamily,
                    onSelected: (_) =>
                        _update(_settings.copyWith(fontFamily: font)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            _slider(
              theme,
              label: 'Text size',
              value: _settings.fontSize,
              min: 14,
              max: 28,
              divisions: 14,
              display: _settings.fontSize.round().toString(),
              onChanged: (v) => _update(_settings.copyWith(fontSize: v)),
            ),
            _slider(
              theme,
              label: 'Line spacing',
              value: _settings.lineHeight,
              min: 1.2,
              max: 2.2,
              divisions: 20,
              display: _settings.lineHeight.toStringAsFixed(2),
              onChanged: (v) => _update(_settings.copyWith(lineHeight: v)),
            ),
            _slider(
              theme,
              label: 'Margins',
              value: _settings.margin,
              min: 8,
              max: 56,
              divisions: 12,
              display: _settings.margin.round().toString(),
              onChanged: (v) => _update(_settings.copyWith(margin: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _slider(
    ThemeData theme, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.titleSmall),
            ),
            Text(
              display,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A tappable theme preview — the page colour with a sample "Aa".
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ReaderThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: preset.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : Colors.black26,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  color: preset.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(preset.name, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
