import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_motion.dart';

/// The moving parts of the Hawthorne Codex look: the ember backdrop behind the
/// tabs, the sheen on a featured panel, and how covers arrive and answer a
/// finger. All of it stops under [AppMotion], and none of it runs in the
/// reader, which is pushed over the shell and so pauses these clocks.

const _ember = Color(0xFFFF4B4B);
const _red = Color(0xFFE5121F);
const _deep = Color(0xFF5A0710);

/// A clock for slow, endless movement: 24 beats a second, which is plenty for
/// something this slow.
///
/// Not a [Ticker], because a ticker asks for every frame the screen can show
/// (120 a second on a recent phone) even when it then draws nothing, and that
/// was what kept the app busy at rest. It runs only while the screen holding it
/// is on show, the app is open and movement is allowed.
///
/// One timer serves everything using it, so a screenful of glimmers all move on
/// the same beat and cost one frame. With a timer each they'd fall out of step
/// and wake the phone many times as often.
mixin SlowClock<T extends StatefulWidget> on State<T> {
  static const _beat = Duration(milliseconds: 41);

  /// One clock for the whole app, so the embers carry on from one screen to
  /// the next instead of jumping back to where they started.
  static final Stopwatch _watch = Stopwatch()..start();
  static final Set<SlowClock> _running = {};
  static Timer? _timer;

  static void _onBeat(Timer _) {
    final now = _watch.elapsedMilliseconds / 1000;
    for (final clock in _running) {
      clock.seconds.value = now;
    }
  }

  late final ValueNotifier<double> seconds = ValueNotifier(
    _watch.elapsedMilliseconds / 1000,
  );
  late final AppLifecycleListener _lifecycle;
  bool _phoneReduced = false;
  bool _onShow = true;

  bool get clockRunning => _running.contains(this);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncClock());
    AppMotion.reduceAnimations.addListener(_syncClock);
    AppMotion.stillScreens.addListener(_syncClock);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here and kept: the listeners can fire while a screen is being taken
    // down, when looking things up through the context is no longer safe.
    _phoneReduced = MediaQuery.of(context).disableAnimations;
    // A tab that isn't chosen stays alive but hidden, and only Visibility says so.
    _onShow = TickerMode.valuesOf(context).enabled && Visibility.of(context);
    _syncClock();
  }

  void _syncClock() {
    if (!mounted) return;
    final life = WidgetsBinding.instance.lifecycleState;
    final open =
        life == null ||
        life == AppLifecycleState.resumed ||
        life == AppLifecycleState.inactive;
    final run =
        open &&
        _onShow &&
        !_phoneReduced &&
        !AppMotion.reduceAnimations.value &&
        AppMotion.stillScreens.value == 0;
    if (run) {
      _running.add(this);
      _timer ??= Timer.periodic(_beat, _onBeat);
    } else {
      _stopClock();
    }
  }

  void _stopClock() {
    _running.remove(this);
    if (_running.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _stopClock();
    _lifecycle.dispose();
    AppMotion.reduceAnimations.removeListener(_syncClock);
    AppMotion.stillScreens.removeListener(_syncClock);
    seconds.dispose();
    super.dispose();
  }
}

/// Every screen in the app, drawn over the embers. Scaffolds inside go clear so
/// they show through, and app bars stay nearly solid: a cover's own title
/// showing through made the heading on top of it hard to read.
class LivingPage extends StatelessWidget {
  const LivingPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const EmberBackdrop(),
        Theme(
          data: theme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            appBarTheme: theme.appBarTheme.copyWith(
              backgroundColor: const Color(0xF2060304),
              scrolledUnderElevation: 0,
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// Gives every pushed screen its [LivingPage], in one place rather than at each
/// of the many spots that open a screen, then moves it the platform's own way.
/// Each page is solid, so nothing of the one beneath shows during the change.
class LivingPageTransitions extends PageTransitionsBuilder {
  const LivingPageTransitions();

  static const _android = ZoomPageTransitionsBuilder();
  static const _ios = CupertinoPageTransitionsBuilder();

  /// Kept per screen: this runs on every frame of a transition, and handing
  /// back the same widget means the page isn't rebuilt each time.
  static final Expando<Widget> _pages = Expando();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final PageTransitionsBuilder inner =
        Theme.of(context).platform == TargetPlatform.iOS ? _ios : _android;
    return inner.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      _pages[route] ??= LivingPage(child: child),
    );
  }
}

/// Slow red light and rising embers.
class EmberBackdrop extends StatefulWidget {
  const EmberBackdrop({super.key});

  @override
  State<EmberBackdrop> createState() => _EmberBackdropState();
}

class _EmberBackdropState extends State<EmberBackdrop> with SlowClock {
  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _EmberPainter(seconds),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _EmberPainter extends CustomPainter {
  _EmberPainter(this.seconds) : super(repaint: seconds);

  final ValueListenable<double> seconds;

  static final List<_Ember> _embers = () {
    final random = math.Random(7);
    return List.generate(26, (_) => _Ember(random));
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds.value;
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF060304));

    _glow(
      canvas,
      bounds,
      Offset(
        size.width * (0.2 + 0.16 * math.sin(t * 0.09)),
        size.height * (0.1 + 0.06 * math.cos(t * 0.07)),
      ),
      size.longestSide * 0.62,
      _red.withValues(alpha: 0.30),
    );
    _glow(
      canvas,
      bounds,
      Offset(
        size.width * (0.85 + 0.14 * math.cos(t * 0.06)),
        size.height * (0.82 + 0.08 * math.sin(t * 0.08)),
      ),
      size.longestSide * 0.7,
      _deep.withValues(alpha: 0.62),
    );

    final source = Offset.zero & const Size.square(_spriteSize);
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final ember in _embers) {
      final rise = (ember.y - t * ember.speed) % 1.0;
      final x = ember.x + 0.022 * math.sin(t * ember.sway + ember.phase);
      final flicker = 0.55 + 0.45 * math.sin(t * ember.flicker + ember.phase);
      // Fade in low and out high, so none of them pop at the edges.
      final edge = math.min(1.0, math.min(rise, 1 - rise) * 6);
      final alpha = (ember.brightness * flicker * edge).clamp(0.0, 1.0);
      final at = Offset(x * size.width, rise * size.height);
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawImageRect(
        _sprite,
        source,
        Rect.fromCircle(center: at, radius: ember.radius * 5),
        paint,
      );
    }
  }

  /// One soft glow, drawn once and stamped for every ember. A blur per ember
  /// per frame would cost far more, and a flat ring around a dot looks like a
  /// target rather than something burning.
  static const _spriteSize = 64.0;
  static final ui.Image _sprite = () {
    final recorder = ui.PictureRecorder();
    const middle = Offset(_spriteSize / 2, _spriteSize / 2);
    final shader = const RadialGradient(
      colors: [Color(0xFFFFC2B0), _ember, Color(0x70E5121F), Color(0x00E5121F)],
      stops: [0, 0.14, 0.34, 1],
    ).createShader(Rect.fromCircle(center: middle, radius: _spriteSize / 2));
    Canvas(
      recorder,
    ).drawCircle(middle, _spriteSize / 2, Paint()..shader = shader);
    return recorder.endRecording().toImageSync(
      _spriteSize.toInt(),
      _spriteSize.toInt(),
    );
  }();

  void _glow(
    Canvas canvas,
    Rect bounds,
    Offset at,
    double radius,
    Color color,
  ) {
    final shader = RadialGradient(
      colors: [color, color.withValues(alpha: 0)],
    ).createShader(Rect.fromCircle(center: at, radius: radius));
    canvas.drawRect(bounds, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_EmberPainter oldDelegate) => false;
}

class _Ember {
  _Ember(math.Random random)
    : x = random.nextDouble(),
      y = random.nextDouble(),
      speed = 0.008 + random.nextDouble() * 0.014,
      sway = 0.2 + random.nextDouble() * 0.4,
      flicker = 0.6 + random.nextDouble() * 1.2,
      phase = random.nextDouble() * math.pi * 2,
      radius = 0.8 + random.nextDouble() * 1.5,
      brightness = 0.35 + random.nextDouble() * 0.55;

  final double x, y, speed, sway, flicker, phase, radius, brightness;
}

/// The moving light on a featured panel: a slow red drift and a sheen passing
/// over it now and then. Goes behind the panel's content.
class PanelGlow extends StatefulWidget {
  const PanelGlow({super.key});

  @override
  State<PanelGlow> createState() => _PanelGlowState();
}

class _PanelGlowState extends State<PanelGlow> with SlowClock {
  static const _cycle = 11.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: seconds,
            builder: (context, elapsed, _) {
              final t = (elapsed % _cycle) / _cycle;
              // The sheen crosses in the first fifth, then the panel rests.
              final sweep = (t / 0.2).clamp(0.0, 1.0);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 2 * math.sin(t * math.pi * 2), -1),
                    end: const Alignment(1, 1),
                    colors: const [Color(0xFF4A0810), Color(0xFF16070A)],
                  ),
                ),
                child: sweep >= 1
                    ? null
                    : FractionalTranslation(
                        translation: Offset(-1 + 3 * sweep, 0),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1, -0.4),
                              end: Alignment(1, 0.4),
                              colors: [
                                Color(0x00FFFFFF),
                                Color(0x1FFFB4B4),
                                Color(0x00FFFFFF),
                              ],
                            ),
                          ),
                          child: SizedBox.expand(),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A small icon that glimmers, like the sparkle on a section heading.
class Twinkle extends StatefulWidget {
  const Twinkle({super.key, required this.child, this.phase = 0});

  final Widget child;

  /// Where in its glimmer it starts, so a screenful don't pulse in step.
  final double phase;

  @override
  State<Twinkle> createState() => _TwinkleState();
}

class _TwinkleState extends State<Twinkle> with SlowClock {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: seconds,
        child: widget.child,
        builder: (context, elapsed, child) {
          final pulse = 0.5 + 0.5 * math.sin(elapsed * 1.4 + widget.phase);
          return Opacity(
            opacity: 0.55 + 0.45 * pulse,
            child: Transform.scale(scale: 0.86 + 0.2 * pulse, child: child),
          );
        },
      ),
    );
  }
}

/// A soft red glow around a featured cover, breathing slowly.
class BreathingGlow extends StatefulWidget {
  const BreathingGlow({
    super.key,
    required this.child,
    required this.borderRadius,
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow> with SlowClock {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: seconds,
        child: widget.child,
        builder: (context, elapsed, child) {
          final pulse = 0.5 + 0.5 * math.sin(elapsed * 0.9);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: [
                BoxShadow(
                  color: _red.withValues(alpha: 0.28 + 0.3 * pulse),
                  blurRadius: 14 + 12 * pulse,
                  spreadRadius: 1 + pulse,
                ),
              ],
            ),
            child: child,
          );
        },
      ),
    );
  }
}

/// Sinks a little under a finger and springs back. Uses a raw pointer listener,
/// so it never competes with the tap, long-press or scroll underneath.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: Duration(milliseconds: _down ? 110 : 320),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Fades and rises into place once, when it first appears.
class RiseIn extends StatelessWidget {
  const RiseIn({super.key, required this.child, this.delayMs = 0});

  final Widget child;

  /// How long it waits first, so a page's sections arrive one after another.
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReduced(context)) return child;
    const riseMs = 460;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: delayMs + riseMs),
      curve: Interval(
        delayMs / (delayMs + riseMs),
        1,
        curve: Curves.easeOutCubic,
      ),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
