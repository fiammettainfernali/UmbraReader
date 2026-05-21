import 'package:flutter/material.dart';

import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../services/tts_service.dart';

/// Font choices offered in the reader. An empty string is the system font.
const List<String> kReaderFonts = [
  '',
  'Literata',
  'Lora',
  'Atkinson Hyperlegible',
];

String _fontLabel(String family) => family.isEmpty ? 'System' : family;

/// Sleep-timer choices for read-aloud. A null [duration] means either "off"
/// or "stop when the current chapter ends".
enum SleepTimerOption {
  off('Off', null),
  m15('15 min', Duration(minutes: 15)),
  m30('30 min', Duration(minutes: 30)),
  m45('45 min', Duration(minutes: 45)),
  m60('60 min', Duration(minutes: 60)),
  endOfChapter('End of chapter', null);

  const SleepTimerOption(this.label, this.duration);

  final String label;
  final Duration? duration;
}

/// Bottom sheet for adjusting reader settings live: layout mode, colour
/// theme, font, text size, line spacing and margins.
class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.initial,
    required this.voices,
    required this.sleepOption,
    required this.onChanged,
    required this.onSleepTimerChanged,
  });

  final ReaderSettings initial;

  /// Installed read-aloud voices to choose from.
  final List<TtsVoice> voices;

  /// The currently active sleep-timer choice.
  final SleepTimerOption sleepOption;

  final ValueChanged<ReaderSettings> onChanged;
  final ValueChanged<SleepTimerOption> onSleepTimerChanged;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _settings;
  late SleepTimerOption _sleepOption;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    _sleepOption = widget.sleepOption;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reader settings',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
            _slider(
              theme,
              label: 'Brightness',
              value: _settings.brightness,
              min: 0.15,
              max: 1.0,
              divisions: 17,
              display: '${(_settings.brightness * 100).round()}%',
              onChanged: (v) => _update(_settings.copyWith(brightness: v)),
            ),
            const SizedBox(height: 16),

            _label(theme, 'Text style'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Bold text'),
              subtitle: const Text('Render all text in a heavier weight'),
              value: _settings.boldText,
              onChanged: (on) =>
                  _update(_settings.copyWith(boldText: on)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Italic text'),
              subtitle: const Text('Render all text in italics'),
              value: _settings.italicText,
              onChanged: (on) =>
                  _update(_settings.copyWith(italicText: on)),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ReaderTextAlign>(
              segments: const [
                ButtonSegment(
                  value: ReaderTextAlign.left,
                  label: Text('Left'),
                  icon: Icon(Icons.format_align_left),
                ),
                ButtonSegment(
                  value: ReaderTextAlign.justify,
                  label: Text('Justified'),
                  icon: Icon(Icons.format_align_justify),
                ),
              ],
              selected: {_settings.textAlign},
              onSelectionChanged: (selection) =>
                  _update(_settings.copyWith(textAlign: selection.first)),
            ),
            const SizedBox(height: 16),

            _label(theme, 'Read aloud'),
            _buildVoicePicker(theme),
            _slider(
              theme,
              label: 'Speech rate',
              value: _settings.speechRate,
              min: 0.25,
              max: 1.0,
              divisions: 15,
              display: _settings.speechRate.toStringAsFixed(2),
              onChanged: (v) => _update(_settings.copyWith(speechRate: v)),
            ),
            const SizedBox(height: 16),

            _label(theme, 'Sleep timer'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in SleepTimerOption.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: option == _sleepOption,
                    onSelected: (_) {
                      setState(() => _sleepOption = option);
                      widget.onSleepTimerChanged(option);
                    },
                  ),
              ],
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

  /// Index of the saved voice within [widget.voices], or -1 for the default.
  int _voiceIndex() {
    for (var i = 0; i < widget.voices.length; i++) {
      if (widget.voices[i].name == _settings.voiceName &&
          widget.voices[i].locale == _settings.voiceLocale) {
        return i;
      }
    }
    return -1;
  }

  Widget _buildVoicePicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('Voice', style: theme.textTheme.titleSmall),
          const SizedBox(width: 16),
          Expanded(
            child: widget.voices.isEmpty
                ? Text(
                    'System default',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium,
                  )
                : DropdownButton<int>(
                    isExpanded: true,
                    alignment: Alignment.centerRight,
                    value: _voiceIndex(),
                    items: [
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('System default'),
                      ),
                      for (var i = 0; i < widget.voices.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${widget.voices[i].name}'
                            '  ·  ${widget.voices[i].locale}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (index) {
                      if (index == null) return;
                      if (index < 0) {
                        _update(
                          _settings.copyWith(voiceName: '', voiceLocale: ''),
                        );
                      } else {
                        final voice = widget.voices[index];
                        _update(
                          _settings.copyWith(
                            voiceName: voice.name,
                            voiceLocale: voice.locale,
                          ),
                        );
                      }
                    },
                  ),
          ),
        ],
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
