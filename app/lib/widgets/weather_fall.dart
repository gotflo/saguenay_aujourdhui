import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ce qui tombe en ce moment, d'après la météo relevée.
enum Falling { snow, rain }

/// « Neige légère », « Pluie faible », « Averses de neige »... La neige passe
/// en premier : « pluie et neige » se voit comme de la neige. Une prévision
/// (« possibilité d'averses », « risque de neige ») ne fait rien tomber.
Falling? fallingFrom(String? condition) {
  final c = condition?.toLowerCase() ?? '';
  if (c.contains('possibilit') || c.contains('risque') || c.contains('probabilit')) return null;
  if (c.contains('neige') || c.contains('poudrerie') || c.contains('flocon')) return Falling.snow;
  if (c.contains('pluie') ||
      c.contains('averse') ||
      c.contains('bruine') ||
      c.contains('grésil') ||
      c.contains('orage')) {
    return Falling.rain;
  }
  return null;
}

/// De la neige ou de la pluie qui tombe doucement derrière le texte, quand il
/// neige ou pleut vraiment. Rien si l'on a demandé moins d'animations.
class WeatherFall extends StatefulWidget {
  const WeatherFall({super.key, required this.falling, required this.color});

  final Falling falling;
  final Color color;

  @override
  State<WeatherFall> createState() => _WeatherFallState();
}

class _WeatherFallState extends State<WeatherFall> with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  // Les mêmes flocons à chaque fois : seul le temps les fait bouger.
  static final _drops = () {
    final r = math.Random(7);
    return [
      for (var i = 0; i < 36; i++)
        (
          x: r.nextDouble(),
          y: r.nextDouble(),
          speed: .6 + r.nextDouble() * .8,
          size: r.nextDouble(),
        ),
    ];
  }();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FallPainter(_clock, widget.falling, widget.color, _drops),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FallPainter extends CustomPainter {
  _FallPainter(this.clock, this.falling, this.color, this.drops) : super(repaint: clock);

  final Animation<double> clock;
  final Falling falling;
  final Color color;
  final List<({double x, double y, double speed, double size})> drops;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final snow = falling == Falling.snow;
    final paint = Paint()
      ..color = color.withValues(alpha: snow ? .26 : .14)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    for (final d in drops) {
      // La pluie tombe quatre fois plus vite que la neige.
      final fall = (d.y + t * d.speed * (snow ? 1.5 : 6)) % 1.0;
      final sway = snow ? math.sin((t * 2 * math.pi * 2) + d.x * 12) * 6 : 0.0;
      final x = d.x * size.width + sway;
      final y = fall * (size.height + 20) - 10;
      if (snow) {
        canvas.drawCircle(Offset(x, y), 1.4 + d.size * 1.8, paint);
      } else {
        canvas.drawLine(Offset(x, y), Offset(x - 2, y + 9 + d.size * 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FallPainter old) => old.falling != falling || old.color != color;
}
