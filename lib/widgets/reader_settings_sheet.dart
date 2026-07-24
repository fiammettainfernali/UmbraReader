import 'package:flutter/material.dart';

import '../feature_flags.dart';
import '../models/reader_settings.dart';
import '../models/reader_theme.dart';
import '../services/custom_theme_store.dart';
import 'pro_sheet.dart';
import '../services/network_tts_service.dart';
import '../services/tts_engine.dart';
import '../services/tts_service.dart';

/// Font choices offered in the reader. An empty string is the system font.
const List<String> kReaderFonts = [
  '',
  'Literata',
  'Lora',
  'Atkinson Hyperlegible',
  'OpenDyslexic',
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

  /// Voices for the currently-selected engine. Seeded with the engine that
  /// was active when the sheet opened, then refreshed when the engine or
  /// server config changes.
  late List<TtsVoice> _voices;
  bool _loadingVoices = false;
  String? _voiceStatus;

  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  /// Reused service for auditioning Kokoro voices.
  NetworkTtsService? _previewService;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    _sleepOption = widget.sleepOption;
    _hasOverride = widget.hasOverride;
    _voices = widget.voices;
    _urlController = TextEditingController(text: _settings.ttsServerUrl);
    _tokenController = TextEditingController(text: _settings.ttsServerToken);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _previewService?.dispose();
    super.dispose();
  }

  /// Loads the voice list for the active engine: the on-device voices, or the
  /// Kokoro server's voices (also reporting reachability).
  Future<void> _loadVoices() async {
    setState(() {
      _loadingVoices = true;
      _voiceStatus = null;
    });
    var voices = const <TtsVoice>[];
    String? status;
    if (_settings.ttsEngine == TtsEngineKind.kokoro) {
      if (_settings.ttsServerUrl.trim().isEmpty) {
        status = 'Enter your server address, then Connect.';
      } else {
        final svc = NetworkTtsService(
          baseUrl: _settings.ttsServerUrl,
          token: _settings.ttsServerToken,
        );
        final ok = await svc.ping();
        voices = ok ? await svc.availableVoices() : const [];
        await svc.dispose();
        status = ok
            ? 'Connected — ${voices.length} voices'
            : 'Could not reach the server. Check the address and token.';
      }
    } else {
      voices = await TtsService().availableVoices();
    }
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voiceStatus = status;
      _loadingVoices = false;
    });
  }

  /// Saves the typed server address/token and (re)loads its voices.
  void _connect() {
    _update(
      _settings.copyWith(
        ttsServerUrl: _urlController.text.trim(),
        ttsServerToken: _tokenController.text.trim(),
      ),
    );
    _loadVoices();
  }

  Future<void> _previewVoice(String voice) async {
    final svc = _previewService ??= NetworkTtsService();
    svc.configure(
      baseUrl: _settings.ttsServerUrl,
      token: _settings.ttsServerToken,
    );
    await svc.previewVoice(voice, rate: _settings.speechRate);
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
            const SizedBox(height: 4),
            // First in the sheet on purpose: this is the one thing you reach
            // for mid-migraine, when scrolling a settings list is the last
            // thing you want to do.
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Migraine mode'),
              subtitle: Text(
                _settings.migraineMode
                    ? 'Your normal settings come back when you switch this off'
                    : 'Dim, soft contrast, no motion, roomier text',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              value: _settings.migraineMode,
              onChanged: (on) =>
                  _update(_settings.copyWith(migraineMode: on)),
            ),
            if (_settings.migraineMode)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Green wash'),
                  subtitle: Text(
                    'Green is the band light-sensitivity tends to spare. '
                    'Turn it off if the colour cast bothers you.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  value: _settings.migraineGreen,
                  onChanged: (on) =>
                      _update(_settings.copyWith(migraineGreen: on)),
                ),
              ),
            const SizedBox(height: 4),
            _section(
              theme,
              icon: Icons.view_agenda_outlined,
              title: 'Layout & motion',
              children: [
                _label(theme, 'Reading mode'),
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
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('TV mode'),
                  subtitle: const Text(
                    'Two-column landscape, full-screen — pair with iOS screen '
                    'mirroring (Control Center → Screen Mirroring) to read on '
                    'a TV with the phone as the remote.',
                  ),
                  value: _settings.tvMode,
                  onChanged: (on) async {
                    if (on &&
                        !await requirePro(
                          context,
                          feature: 'TV & spread reading mode',
                        )) {
                      return;
                    }
                    _update(_settings.copyWith(tvMode: on));
                  },
                ),
                const SizedBox(height: 8),
                _label(theme, 'Orientation'),
                SegmentedButton<ReaderOrientation>(
                  segments: const [
                    ButtonSegment(
                      value: ReaderOrientation.auto,
                      label: Text('Auto'),
                      icon: Icon(Icons.screen_rotation),
                    ),
                    ButtonSegment(
                      value: ReaderOrientation.portrait,
                      label: Text('Portrait'),
                      icon: Icon(Icons.stay_current_portrait),
                    ),
                    ButtonSegment(
                      value: ReaderOrientation.landscape,
                      label: Text('Landscape'),
                      icon: Icon(Icons.stay_current_landscape),
                    ),
                  ],
                  selected: {_settings.orientation},
                  onSelectionChanged: (selection) =>
                      _update(_settings.copyWith(orientation: selection.first)),
                ),
                const SizedBox(height: 16),

                _label(theme, 'Hands-free & glasses'),
                const SizedBox(height: 4),
                // One-tap preset tuned for XR glasses (e.g. Viture): landscape,
                // a centred column for the lenses' sharp centre, a soft true-black
                // theme, and keep-awake since the phone is the source display.
                OutlinedButton.icon(
                  onPressed: () => _update(
                    _settings.copyWith(
                      orientation: ReaderOrientation.landscape,
                      centeredColumn: true,
                      keepAwake: true,
                      themeId: 'black',
                    ),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Glasses mode'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Centred column'),
                  subtitle: const Text(
                    'Keep text in a comfortable centred column with wide margins.',
                  ),
                  value: _settings.centeredColumn,
                  onChanged: (on) =>
                      _update(_settings.copyWith(centeredColumn: on)),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Keep screen awake'),
                  subtitle: const Text(
                    'Stop the screen sleeping while reading — useful with glasses '
                    'or auto page-turn.',
                  ),
                  value: _settings.keepAwake,
                  onChanged: (on) => _update(_settings.copyWith(keepAwake: on)),
                ),
                const SizedBox(height: 8),
                _label(theme, 'Auto-turn pages (paged mode)'),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Off')),
                    ButtonSegment(value: 20, label: Text('20s')),
                    ButtonSegment(value: 30, label: Text('30s')),
                    ButtonSegment(value: 45, label: Text('45s')),
                    ButtonSegment(value: 60, label: Text('60s')),
                  ],
                  selected: {_settings.autoPageSeconds},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      _update(_settings.copyWith(autoPageSeconds: s.first)),
                ),
              ],
            ),
            _section(
              theme,
              icon: Icons.touch_app_outlined,
              title: 'Tap zones & gestures',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Tap edges to turn pages'),
                  subtitle: const Text(
                    'Tap the left/right edges to turn pages. Off: only a swipe '
                    'or remote turns pages, so a stray tap never does.',
                  ),
                  value: _settings.tapTurnZones,
                  onChanged: (on) =>
                      _update(_settings.copyWith(tapTurnZones: on)),
                ),
                if (_settings.tapTurnZones) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Left-handed'),
                    subtitle: const Text(
                      'Swap sides: tap left to go forward, right to go back.',
                    ),
                    value: _settings.leftHandedTaps,
                    onChanged: (on) =>
                        _update(_settings.copyWith(leftHandedTaps: on)),
                  ),
                  _slider(
                    theme,
                    label: 'Turn-zone size',
                    value: _settings.tapZoneWidth,
                    min: 0.15,
                    max: 0.45,
                    divisions: 6,
                    display: '${(_settings.tapZoneWidth * 100).round()}%',
                    onChanged: (v) =>
                        _update(_settings.copyWith(tapZoneWidth: v)),
                  ),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Slide left edge for brightness'),
                  subtitle: const Text(
                    'Drag up or down along the left edge to dim or brighten.',
                  ),
                  value: _settings.edgeBrightnessGesture,
                  onChanged: (on) =>
                      _update(_settings.copyWith(edgeBrightnessGesture: on)),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Animate page turns'),
                  subtitle: const Text(
                    'Off: pages snap instantly, without turning off other '
                    'animations.',
                  ),
                  value: _settings.pageAnimations,
                  onChanged: (on) =>
                      _update(_settings.copyWith(pageAnimations: on)),
                ),
                const SizedBox(height: 8),
                _label(theme, 'Double-tap'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<ReaderDoubleTap>(
                    value: _settings.doubleTapAction,
                    onChanged: (v) => v == null
                        ? null
                        : _update(_settings.copyWith(doubleTapAction: v)),
                    items: const [
                      DropdownMenuItem(
                        value: ReaderDoubleTap.none,
                        child: Text('Nothing'),
                      ),
                      DropdownMenuItem(
                        value: ReaderDoubleTap.bookmark,
                        child: Text('Add bookmark'),
                      ),
                      DropdownMenuItem(
                        value: ReaderDoubleTap.contents,
                        child: Text('Table of contents'),
                      ),
                      DropdownMenuItem(
                        value: ReaderDoubleTap.bookmarksList,
                        child: Text('Bookmarks'),
                      ),
                    ],
                  ),
                ),
                if (_settings.doubleTapAction != ReaderDoubleTap.none)
                  Text(
                    'Single taps wait a moment to tell a double-tap apart.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            _section(
              theme,
              icon: Icons.palette_outlined,
              title: 'Appearance',
              children: [
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
                        child: _NewThemeTile(
                          onTap: () async {
                            if (!await requirePro(
                              context,
                              feature: 'Custom reading themes',
                            )) {
                              return;
                            }
                            _createCustomTheme();
                          },
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
                  label: 'Letter spacing',
                  value: _settings.letterSpacing.clamp(0.0, 4.0),
                  min: 0,
                  max: 4,
                  divisions: 8,
                  display: '${_settings.letterSpacing.toStringAsFixed(1)} px',
                  onChanged: (v) =>
                      _update(_settings.copyWith(letterSpacing: v)),
                ),
                _slider(
                  theme,
                  label: 'Word spacing',
                  value: _settings.wordSpacing.clamp(0.0, 8.0),
                  min: 0,
                  max: 8,
                  divisions: 8,
                  display: '${_settings.wordSpacing.round()} px',
                  onChanged: (v) => _update(_settings.copyWith(wordSpacing: v)),
                ),
                _slider(
                  theme,
                  label: 'Paragraph spacing',
                  value: _settings.paragraphSpacing.clamp(0.0, 24.0),
                  min: 0,
                  max: 24,
                  divisions: 12,
                  display: '${_settings.paragraphSpacing.round()} px',
                  onChanged: (v) =>
                      _update(_settings.copyWith(paragraphSpacing: v)),
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

                _label(theme, 'Colour overlay'),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tint in kOverlayTints)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _TintSwatch(
                            tint: tint,
                            base: readerThemeById(_settings.themeId),
                            // A tint at zero strength is invisible, so pick
                            // one and give it a usable default rather than
                            // leaving the reader looking broken.
                            severity: _settings.overlaySeverity == 0
                                ? 0.5
                                : _settings.overlaySeverity,
                            selected: tint.id == _settings.overlayTint,
                            onTap: () => _update(
                              _settings.copyWith(
                                overlayTint: tint.id,
                                overlaySeverity:
                                    tint.id != kOverlayTintNone &&
                                        _settings.overlaySeverity == 0
                                    ? 0.5
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_settings.overlayTint != kOverlayTintNone)
                  _slider(
                    theme,
                    label: 'Overlay strength',
                    value: _settings.overlaySeverity,
                    min: 0.05,
                    max: 1.0,
                    divisions: 19,
                    display: '${(_settings.overlaySeverity * 100).round()}%',
                    onChanged: (v) =>
                        _update(_settings.copyWith(overlaySeverity: v)),
                  ),
                const SizedBox(height: 16),

                _label(theme, 'Text style'),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Bold text'),
                  subtitle: const Text('Render all text in a heavier weight'),
                  value: _settings.boldText,
                  onChanged: (on) => _update(_settings.copyWith(boldText: on)),
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
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Fixation anchors'),
                  subtitle: const Text(
                    'Bold the first letters of each word as eye-anchors — a '
                    'reading aid that can make text easier to track',
                  ),
                  value: _settings.fixationAnchors,
                  onChanged: (on) =>
                      _update(_settings.copyWith(fixationAnchors: on)),
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
                  title: const Text('Reading ruler'),
                  subtitle: const Text(
                    'Dim everything except a few lines — a focus aid; the '
                    'text moves through the bright band',
                  ),
                  value: _settings.lineFocus,
                  onChanged: (on) =>
                      _update(_settings.copyWith(lineFocus: on)),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Focus paragraph'),
                  subtitle: const Text(
                    'Show one paragraph at a time, centred — tap the sides to '
                    'move; a calmer view when a full page is overwhelming',
                  ),
                  value: _settings.focusParagraph,
                  onChanged: (on) =>
                      _update(_settings.copyWith(focusParagraph: on)),
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
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Reduce animations'),
                  subtitle: const Text(
                    'Page turns and scrolls jump instantly instead of sliding',
                  ),
                  value: _settings.reduceAnimations,
                  onChanged: (on) =>
                      _update(_settings.copyWith(reduceAnimations: on)),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Haptic feedback'),
                  subtitle: const Text(
                    'Small taps on page turns and advances',
                  ),
                  value: _settings.hapticFeedback,
                  onChanged: (on) =>
                      _update(_settings.copyWith(hapticFeedback: on)),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Exact numbers'),
                  subtitle: const Text(
                    'Page counts, percentages and minutes shown precisely '
                    'instead of "~5 min" approximations',
                  ),
                  value: _settings.exactNumbers,
                  onChanged: (on) =>
                      _update(_settings.copyWith(exactNumbers: on)),
                ),
                const SizedBox(height: 12),
                _label(theme, 'Session timer'),
                Text(
                  'A quiet fill tracks your reading time; passing it offers a '
                  'gentle break check-in between chapters — never an alarm.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in const [0, 15, 30, 45, 60])
                      ChoiceChip(
                        label: Text(m == 0 ? 'Off' : '$m min'),
                        selected: _settings.sessionMinutes == m,
                        onSelected: (_) =>
                            _update(_settings.copyWith(sessionMinutes: m)),
                      ),
                  ],
                ),
              ],
            ),
            if (kReadAloudEnabled)
              _section(
                theme,
                icon: Icons.graphic_eq,
                title: 'Read aloud',
                expanded: true,
                children: [
                  _label(theme, 'Engine'),
                  SegmentedButton<TtsEngineKind>(
                    segments: const [
                      ButtonSegment(
                        value: TtsEngineKind.system,
                        label: Text('On-device'),
                        icon: Icon(Icons.phone_iphone),
                      ),
                      ButtonSegment(
                        value: TtsEngineKind.kokoro,
                        label: Text('Natural'),
                        icon: Icon(Icons.auto_awesome),
                      ),
                    ],
                    selected: {_settings.ttsEngine},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      _update(_settings.copyWith(ttsEngine: selection.first));
                      _loadVoices();
                    },
                  ),
                  if (_settings.ttsEngine == TtsEngineKind.kokoro) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Streams natural neural voices from your own desktop '
                      'voice server over Tailscale. Include the http:// scheme '
                      'and port, e.g. http://100.x.y.z:8080.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Server address',
                        hintText: 'http://100.x.y.z:8080',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Access token',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _loadingVoices ? null : _connect,
                          icon: _loadingVoices
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.link),
                          label: const Text('Connect'),
                        ),
                        const SizedBox(width: 12),
                        if (_voiceStatus != null)
                          Expanded(
                            child: Text(
                              _voiceStatus!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  _label(theme, 'Voice & speed'),
                  _buildVoicePicker(theme),
                  _slider(
                    theme,
                    label: 'Speed',
                    value: _settings.speechRate.clamp(0.25, 1.5),
                    min: 0.25,
                    max: 1.5,
                    divisions: 10,
                    display: _speedMultiplier(_settings.speechRate),
                    onChanged: (v) =>
                        _update(_settings.copyWith(speechRate: v)),
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

  /// A collapsible settings group, so the sheet reads as a few scannable
  /// sections rather than one long wall of controls.
  Widget _section(
    ThemeData theme, {
    required IconData icon,
    required String title,
    bool expanded = false,
    required List<Widget> children,
  }) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: children,
      ),
    );
  }

  /// Index of the saved voice within [_voices], or -1 for the default.
  int _voiceIndex() {
    for (var i = 0; i < _voices.length; i++) {
      if (_voices[i].name == _settings.voiceName &&
          _voices[i].locale == _settings.voiceLocale) {
        return i;
      }
    }
    return -1;
  }

  static const _voiceAccents = {
    'a': 'American',
    'b': 'British',
    'e': 'Spanish',
    'f': 'French',
    'h': 'Hindi',
    'i': 'Italian',
    'j': 'Japanese',
    'p': 'Portuguese',
    'z': 'Mandarin',
  };

  /// A friendly label for a voice — the given name plus accent/gender for
  /// Kokoro voices (e.g. `af_heart` → "Heart · American, Female").
  String _friendlyVoiceLabel(TtsVoice voice) {
    if (!voice.isKokoro) return '${voice.name} · ${voice.locale}';
    final parts = voice.name.split('_');
    if (parts.length == 2 && parts[0].length == 2 && parts[1].isNotEmpty) {
      final accent = _voiceAccents[parts[0][0]] ?? '';
      final gender = parts[0][1] == 'm'
          ? 'Male'
          : parts[0][1] == 'f'
          ? 'Female'
          : '';
      final given = parts[1][0].toUpperCase() + parts[1].substring(1);
      final tag = [accent, gender].where((s) => s.isNotEmpty).join(', ');
      return tag.isEmpty ? given : '$given · $tag';
    }
    return voice.name;
  }

  Widget _buildVoicePicker(ThemeData theme) {
    final selected = _voiceIndex();
    final label = selected >= 0
        ? _friendlyVoiceLabel(_voices[selected])
        : 'System default';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Voice'),
      subtitle: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: _voices.isEmpty ? null : _openVoiceSheet,
    );
  }

  /// Opens the searchable voice list; applies the chosen voice on return.
  Future<void> _openVoiceSheet() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      builder: (_) => _VoiceSheet(
        voices: _voices,
        selectedIndex: _voiceIndex(),
        labelFor: _friendlyVoiceLabel,
        onPreview: _previewVoice,
      ),
    );
    if (result == null) return;
    if (result < 0) {
      _update(_settings.copyWith(voiceName: '', voiceLocale: ''));
    } else {
      final voice = _voices[result];
      _update(
        _settings.copyWith(voiceName: voice.name, voiceLocale: voice.locale),
      );
    }
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
        content: const Text(
          'This removes the custom theme. The built-in '
          'themes are not affected.',
        ),
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

  /// Read-aloud speed as a playback multiplier, e.g. "1.5×".
  String _speedMultiplier(double rate) {
    final m = rate * 2;
    var s = m.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return '$s×';
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
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
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

/// A searchable list of read-aloud voices, with per-voice preview. Pops the
/// chosen voice index (or -1 for "System default"); null when dismissed.
class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet({
    required this.voices,
    required this.selectedIndex,
    required this.labelFor,
    required this.onPreview,
  });

  final List<TtsVoice> voices;
  final int selectedIndex;
  final String Function(TtsVoice) labelFor;
  final Future<void> Function(String voice) onPreview;

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final matches = <int>[
      for (var i = 0; i < widget.voices.length; i++)
        if (q.isEmpty ||
            widget.labelFor(widget.voices[i]).toLowerCase().contains(q) ||
            widget.voices[i].name.toLowerCase().contains(q))
          i,
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a voice',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search voices',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (q.isEmpty)
                    ListTile(
                      title: const Text('System default'),
                      selected: widget.selectedIndex < 0,
                      trailing: widget.selectedIndex < 0
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(context).pop(-1),
                    ),
                  for (final i in matches)
                    ListTile(
                      title: Text(widget.labelFor(widget.voices[i])),
                      selected: i == widget.selectedIndex,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.voices[i].isKokoro)
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline),
                              tooltip: 'Preview',
                              onPressed: () =>
                                  widget.onPreview(widget.voices[i].name),
                            ),
                          if (i == widget.selectedIndex)
                            const Icon(Icons.check),
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.name} reading theme',
      excludeSemantics: true,
      child: GestureDetector(
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
      ),
    );
  }
}

/// One overlay-tint choice, previewed as the wash actually looks over the
/// reader's current theme rather than as a swatch of the raw tint colour.
class _TintSwatch extends StatelessWidget {
  const _TintSwatch({
    required this.tint,
    required this.base,
    required this.severity,
    required this.selected,
    required this.onTap,
  });

  final ReaderOverlayTint tint;

  /// The untinted theme the preview washes over.
  final ReaderThemePreset base;

  final double severity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final washed = base.withOverlay(tint, severity);
    return Semantics(
      button: true,
      selected: selected,
      label: tint.id == kOverlayTintNone
          ? 'No colour overlay'
          : '${tint.name} colour overlay',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: washed.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? accent : Colors.black26,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: Center(
                child: tint.id == kOverlayTintNone
                    ? Icon(Icons.block, size: 20, color: washed.secondary)
                    : Text(
                        'Aa',
                        style: TextStyle(
                          color: washed.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(tint.name, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
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
    return Semantics(
      button: true,
      label: 'Create a new reading theme',
      excludeSemantics: true,
      child: GestureDetector(
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
    _bgController = TextEditingController(
      text: _formatHex(widget.base.background),
    );
    _textController = TextEditingController(text: _formatHex(widget.base.text));
    _secondaryController = TextEditingController(
      text: _formatHex(widget.base.secondary),
    );
    _highlightController = TextEditingController(
      text: _formatHex(widget.base.highlight),
    );
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
