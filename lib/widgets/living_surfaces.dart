import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
mixin SlowClock<T extends StatefulWidget> on State<T> {
  static const _beat = Duration(milliseconds: 41);

  final ValueNotifier<double> seconds = ValueNotifier(0);
  final Stopwatch _watch = Stopwatch();
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;

  bool get clockRunning => _timer != null;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncClock());
    AppMotion.reduceAnimations.addListener(_syncClock);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
        TickerMode.valuesOf(context).enabled &&
        !AppMotion.isReduced(context);
    if (run && _timer == null) {
      _watch.start();
      _timer = Timer.periodic(_beat, (_) {
        seconds.value = _watch.elapsedMilliseconds / 1000;
      });
    } else if (!run && _timer != null) {
      _watch.stop();
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    AppMotion.reduceAnimations.removeListener(_syncClock);
    seconds.dispose();
    super.dispose();
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
  const RiseIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
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
