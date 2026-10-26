import 'package:flutter/material.dart';

/// Le logo : un soleil au-dessus d'une vague, sur un rond jaune.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 32, this.filled = true});

  final double size;

  /// Sans le rond jaune, pour poser le dessin sur un fond déjà jaune.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LogoPainter(filled)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.filled);

  final bool filled;
  static const _sun = Color(0xFFFFD02B);
  static const _ink = Color(0xFF1A1906);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32;
    if (filled) {
      canvas.drawCircle(Offset(16 * s, 16 * s), 16 * s, Paint()..color = _sun);
    }
    final wave = Path()
      ..moveTo(6 * s, 19.5 * s)
      ..cubicTo(9.2 * s, 16.5 * s, 12.4 * s, 16.5 * s, 15.6 * s, 19.5 * s)
      ..cubicTo(18.8 * s, 22.5 * s, 22 * s, 22.5 * s, 26 * s, 19.1 * s);
    canvas.drawPath(
      wave,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * s
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(20.5 * s, 11.5 * s), 2.6 * s, Paint()..color = _ink);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.filled != filled;
}
