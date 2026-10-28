import 'package:flutter/material.dart';

/// Les deux habillages de l'app.
enum AppPalette {
  /// Jaune déneigeuse et noir : l'identité du projet.
  saguenayAujourdhui('Saguenay Aujourd’hui'),

  /// Le bleu de la Ville de Saguenay, relevé sur ville.saguenay.ca.
  /// À montrer à la Ville, et à utiliser publiquement seulement avec son accord.
  ville('Ville de Saguenay');

  const AppPalette(this.label);

  final String label;
}

/// Une couleur d'accent, des neutres, et une couleur par type d'information.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.card,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.blue,
    required this.aqua,
    required this.green,
    required this.red,
    required this.orange,
    required this.amber,
    required this.violet,
    required this.slate,
    required this.pink,
    required this.stone,
    required this.critical,
    required this.glass,
    required this.glassEdge,
    required this.glassShadow,
    required this.sheet,
    required this.haloWarm,
    required this.haloCool,
  });

  final Color bg;
  final Color card;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;

  /// Fond de la carte du haut et des moments forts.
  final Color accent;
  final Color onAccent;
  final Color accentSoft;

  final Color blue;
  final Color aqua;
  final Color green;
  final Color red;
  final Color orange;
  final Color amber;
  final Color violet;

  /// Météo.
  final Color slate;

  /// Électricité.
  final Color pink;

  /// Routes.
  final Color stone;

  /// Fond des alertes de santé (avis d’ébullition), assez foncé pour du texte blanc.
  final Color critical;

  /// Le verre dépoli des cartes : un voile translucide, un liseré lumineux,
  /// une ombre à peine marquée.
  final Color glass;
  final Color glassEdge;
  final Color glassShadow;

  /// Les feuilles du bas, plus couvrantes que les cartes : elles passent sur
  /// du texte.
  final Color sheet;

  /// Les deux halos du fond, que le verre laisse deviner.
  final Color haloWarm;
  final Color haloCool;

  static AppColors of(AppPalette palette, Brightness brightness) => switch ((palette, brightness)) {
    (AppPalette.saguenayAujourdhui, Brightness.light) => light,
    (AppPalette.saguenayAujourdhui, Brightness.dark) => dark,
    (AppPalette.ville, Brightness.light) => villeLight,
    (AppPalette.ville, Brightness.dark) => villeDark,
  };

  static const light = AppColors(
    bg: Color(0xFFF1F2EF),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF121417),
    ink2: Color(0xFF4A5056),
    ink3: Color(0xFF62676D),
    line: Color(0xFFE1E3DF),
    accent: Color(0xFFFFD02B),
    onAccent: Color(0xFF1A1906),
    accentSoft: Color(0xFFFFF3C4),
    blue: Color(0xFF2F6BEB),
    aqua: Color(0xFF1A8FC4),
    green: Color(0xFF1C9A5F),
    red: Color(0xFFE0453F),
    orange: Color(0xFFE77A0C),
    amber: Color(0xFFB7791F),
    violet: Color(0xFF6B55C9),
    slate: Color(0xFF4E6A85),
    pink: Color(0xFFC23D74),
    stone: Color(0xFF7A6650),
    critical: Color(0xFFC4302B),
    glass: Color(0xA6FFFFFF),
    glassEdge: Color(0xCCFFFFFF),
    glassShadow: Color(0x0F1A1906),
    sheet: Color(0xE6FFFFFF),
    haloWarm: Color(0x66FFD02B),
    haloCool: Color(0x2E1A8FC4),
  );

  static const dark = AppColors(
    bg: Color(0xFF0F1113),
    card: Color(0xFF1B1E22),
    ink: Color(0xFFF1F2F3),
    ink2: Color(0xFFB3B9BF),
    ink3: Color(0xFF8A9198),
    line: Color(0xFF2A2E33),
    accent: Color(0xFFFFD02B),
    onAccent: Color(0xFF1A1906),
    accentSoft: Color(0xFF3A3212),
    blue: Color(0xFF6C9BFF),
    aqua: Color(0xFF4DB8E8),
    green: Color(0xFF3FC184),
    red: Color(0xFFFF6B63),
    orange: Color(0xFFFF9B3D),
    amber: Color(0xFFF2B544),
    violet: Color(0xFF9E8CFF),
    slate: Color(0xFF9DB6CC),
    pink: Color(0xFFFF8AB6),
    stone: Color(0xFFCDB89C),
    critical: Color(0xFFB42F2A),
    glass: Color(0x991B1E22),
    glassEdge: Color(0x1FFFFFFF),
    glassShadow: Color(0x00000000),
    sheet: Color(0xE61B1E22),
    haloWarm: Color(0x1AFFD02B),
    haloCool: Color(0x1F4DB8E8),
  );

  // Bleu #0053A0, bleu vif #0562C1, gris-bleus #D8E2EC et #E8EEF4, ardoise
  // #485159, vert #33AB62 et rouge #DF1B1C : les couleurs du site de la Ville.
  static const villeLight = AppColors(
    bg: Color(0xFFEEF2F6),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF16212C),
    ink2: Color(0xFF485159),
    ink3: Color(0xFF5B6670),
    line: Color(0xFFD8E2EC),
    accent: Color(0xFF0053A0),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE8EEF4),
    blue: Color(0xFF0562C1),
    aqua: Color(0xFF1A8FC4),
    green: Color(0xFF2B9656),
    red: Color(0xFFDF1B1C),
    orange: Color(0xFFE07A10),
    amber: Color(0xFFB7791F),
    violet: Color(0xFF6B55C9),
    slate: Color(0xFF4E6A85),
    pink: Color(0xFFC23D74),
    stone: Color(0xFF7A6650),
    critical: Color(0xFFC4302B),
    glass: Color(0xA6FFFFFF),
    glassEdge: Color(0xCCFFFFFF),
    glassShadow: Color(0x0F16212C),
    sheet: Color(0xE6FFFFFF),
    haloWarm: Color(0x140562C1),
    haloCool: Color(0x2E33AB62),
  );

  static const villeDark = AppColors(
    bg: Color(0xFF0C131C),
    card: Color(0xFF162231),
    ink: Color(0xFFEEF2F6),
    ink2: Color(0xFFB9CBDD),
    ink3: Color(0xFF8DA0B4),
    line: Color(0xFF243447),
    accent: Color(0xFF175FAD),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFF1A2D44),
    blue: Color(0xFF5B9BE6),
    aqua: Color(0xFF4DB8E8),
    green: Color(0xFF4CC17E),
    red: Color(0xFFFF6B63),
    orange: Color(0xFFFF9B3D),
    amber: Color(0xFFF2B544),
    violet: Color(0xFF9E8CFF),
    slate: Color(0xFF9DB6CC),
    pink: Color(0xFFFF8AB6),
    stone: Color(0xFFCDB89C),
    critical: Color(0xFFB42F2A),
    glass: Color(0x99162231),
    glassEdge: Color(0x1FFFFFFF),
    glassShadow: Color(0x00000000),
    sheet: Color(0xE6162231),
    haloWarm: Color(0x335B9BE6),
    haloCool: Color(0x1F4CC17E),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < .5 ? this : other;
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
