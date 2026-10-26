import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/theme/colors.dart';

/// Rapport de contraste WCAG entre deux couleurs opaques.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + .05) / (lo + .05);
}

/// [fg] posé sur [bg] avec une opacité donnée.
Color over(Color fg, Color bg, double alpha) => Color.lerp(bg, fg, alpha)!;

void main() {
  final themes = {
    for (final p in AppPalette.values)
      for (final b in Brightness.values) '${p.name} ${b.name}': AppColors.of(p, b),
  };

  for (final MapEntry(key: name, value: c) in themes.entries) {
    group(name, () {
      test('texte courant sur le fond et sur les cartes (4,5:1)', () {
        expect(contrast(c.ink, c.bg), greaterThanOrEqualTo(7));
        expect(contrast(c.ink2, c.card), greaterThanOrEqualTo(4.5));
        expect(contrast(c.ink2, c.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(c.ink3, c.card), greaterThanOrEqualTo(4.5));
        expect(contrast(c.ink3, c.bg), greaterThanOrEqualTo(4.5));
      });

      test('la carte du haut reste lisible, même en texte adouci', () {
        expect(contrast(over(c.onAccent, c.accent, .82), c.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(Colors.white, c.critical), greaterThanOrEqualTo(4.5));
      });

      test('le verre reste lisible, même sur le halo le plus fort', () {
        // Le fond sous le halo chaud, puis le voile de verre par-dessus.
        final halo = over(c.haloWarm.withValues(alpha: 1), c.bg, c.haloWarm.a);
        for (final (name, veil) in [('carte', c.glass), ('feuille', c.sheet)]) {
          final surface = over(veil.withValues(alpha: 1), halo, veil.a);
          expect(contrast(c.ink, surface), greaterThanOrEqualTo(7), reason: name);
          expect(contrast(c.ink2, surface), greaterThanOrEqualTo(4.5), reason: name);
          expect(contrast(c.ink3, surface), greaterThanOrEqualTo(4.5), reason: name);
        }
        expect(contrast(c.ink3, halo), greaterThanOrEqualTo(4.5), reason: 'fond');
      });

      test('la puce « Démo » et le bouton principal', () {
        expect(contrast(c.ink, c.accentSoft), greaterThanOrEqualTo(4.5));
        expect(contrast(c.bg, c.ink), greaterThanOrEqualTo(7));
      });
    });
  }
}
