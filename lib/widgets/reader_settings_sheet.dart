import 'package:flutter/material.dart';

import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../services/custom_theme_store.dart';
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
    required this.hasOverride,
    required this.onOverrideToggled,
  });

  final ReaderSettings initial;

  /// Installed read-aloud voices to choose from.
  final List<TtsVoice> voices;

  /// The currently active sleep-timer choice.
  final SleepTimerOption sleepOption;

  final ValueChanged<ReaderSettings> onChanged;
  final ValueChanged<SleepTimerOption> onSleepTimerChanged;

  /// True when the current book has its own typography settings stored —
  /// changes from this sheet only affect this volume, not the global defaults.
  final bool hasOverride;

  /// Fired when the user flips the per-book override switch.
  final ValueChanged<bool> onOverrideToggled;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _settings;
  late SleepTimerOption _sleepOption;
  late bool _hasOverride;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    _sleepOption = widget.sleepOption;
    _hasOverride = widget.hasOverride;
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
            // A book-scoped override: when off, changes here mutate the
            // global defaults; when on, they only stick to this volume.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Just for this book'),
              subtitle: Text(
                _hasOverride
                    ? 'Changes only affect this volume'
                    : 'Changes update your global reader defaults',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              value: _hasOverride,
              onChanged: (value) {
                setState(() => _hasOverride = value);
                widget.onOverrideToggled(value);
              },
            ),
            const SizedBox(height: 8),
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
                  for (final preset in CustomThemeStore.all)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _ThemeSwatch(
                        preset: preset,
                        selected: preset.id == _settings.themeId,
                        onTap: () =>
                            _update(_settings.copyWith(themeId: preset.id)),
                        onLongPress: preset.id.startsWith('custom-')
                            ? () => _confirmDeleteTheme(preset)
                            : null,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _NewThemeTile(onTap: _createCustomTheme),
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Auto-scroll'),
              subtitle: const Text(
                'Slowly scrolls scroll-mode for hands-free reading',
              ),
              value: _settings.autoScroll,
              onChanged: (on) =>
                  _update(_settings.copyWith(autoScroll: on)),
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

  /// Opens the colour-editor dialog and, on save, persists the new custom
  /// theme + selects it as the active one.
  Future<void> _createCustomTheme() async {
    final base = readerThemeById(_settings.themeId);
    final result = await showDialog<ReaderThemePreset>(
      context: context,
      builder: (_) => _CustomThemeEditor(base: base),
    );
    if (result == null) return;
    await CustomThemeStore().save(result);
    if (!mounted) return;
    setState(() {});
    _update(_settings.copyWith(themeId: result.id));
  }

  /// Confirms then deletes a user-created theme. If the deleted theme was
  /// the active one, falls back to "dark".
  Future<void> _confirmDeleteTheme(ReaderThemePreset preset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "${preset.name}"?'),
        content: const Text('This removes the custom theme. The built-in '
            'themes are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await CustomThemeStore().delete(preset.id);
    if (!mounted) return;
    setState(() {});
    if (_settings.themeId == preset.id) {
      _update(_settings.copyWith(themeId: 'dark'));
    }
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
    this.onLongPress,
  });

  final ReaderThemePreset preset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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

/// "+ New theme" tile rendered alongside the theme swatches.
class _NewThemeTile extends StatelessWidget {
  const _NewThemeTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          DottedSquare(
            color: theme.colorScheme.outline,
            child: Icon(
              Icons.add,
              color: theme.colorScheme.outline,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text('New', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// A 56×56 rounded-square placeholder with a dashed border — visual cue for
/// the "add a new theme" tile next to the existing swatches.
class DottedSquare extends StatelessWidget {
  const DottedSquare({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Center(child: child),
    );
  }
}

/// Hex-input editor for a custom reader theme. Pops the saved
/// [ReaderThemePreset] when the user taps Save, or null on cancel.
class _CustomThemeEditor extends StatefulWidget {
  const _CustomThemeEditor({required this.base});

  /// Starting colours — usually the user's currently-selected theme.
  final ReaderThemePreset base;

  @override
  State<_CustomThemeEditor> createState() => _CustomThemeEditorState();
}

class _CustomThemeEditorState extends State<_CustomThemeEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _bgController;
  late final TextEditingController _textController;
  late final TextEditingController _secondaryController;
  late final TextEditingController _highlightController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'My theme');
    _bgController = TextEditingController(text: _formatHex(widget.base.background));
    _textController = TextEditingController(text: _formatHex(widget.base.text));
    _secondaryController =
        TextEditingController(text: _formatHex(widget.base.secondary));
    _highlightController =
        TextEditingController(text: _formatHex(widget.base.highlight));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bgController.dispose();
    _textController.dispose();
    _secondaryController.dispose();
    _highlightController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final bg = _parseHex(_bgController.text);
    final text = _parseHex(_textController.text);
    final secondary = _parseHex(_secondaryController.text);
    final highlight = _parseHex(_highlightController.text);
    if (name.isEmpty) {
      setState(() => _error = 'Give the theme a name.');
      return;
    }
    if (bg == null || text == null || secondary == null || highlight == null) {
      setState(() => _error = 'Each colour needs a 6-digit hex (#RRGGBB).');
      return;
    }
    final id = 'custom-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      ReaderThemePreset(
        id: id,
        name: name,
        background: bg,
        text: text,
        secondary: secondary,
        highlight: highlight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New theme'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _hexRow('Background', _bgController),
            const SizedBox(height: 8),
            _hexRow('Text', _textController),
            const SizedBox(height: 8),
            _hexRow('Accent', _secondaryController),
            const SizedBox(height: 8),
            _hexRow('Highlight', _highlightController),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _hexRow(String label, TextEditingController controller) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '#1a1a2e',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        const SizedBox(width: 8),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final c = _parseHex(controller.text);
            return Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c ?? Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black26),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Parses a CSS-style hex colour string into a Color. Accepts optional
/// leading `#`, 6 or 8 hex digits. Returns null for anything malformed.
Color? _parseHex(String input) {
  var s = input.trim().toLowerCase();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length != 6 && s.length != 8) return null;
  final value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  if (s.length == 6) return Color(0xFF000000 | value);
  return Color(value);
}

/// Formats a [Color] as `#rrggbb`.
String _formatHex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}
