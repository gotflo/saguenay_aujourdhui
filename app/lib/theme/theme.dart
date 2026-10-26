import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';
import '../widgets/glass.dart';

abstract final class AppTheme {
  static ThemeData light({
    AppPalette palette = AppPalette.saguenayAujourdhui,
    bool googleFonts = true,
  }) => _build(AppColors.of(palette, Brightness.light), Brightness.light, googleFonts);

  static ThemeData dark({
    AppPalette palette = AppPalette.saguenayAujourdhui,
    bool googleFonts = true,
  }) => _build(AppColors.of(palette, Brightness.dark), Brightness.dark, googleFonts);

  static ThemeData _build(AppColors c, Brightness brightness, bool googleFonts) {
    final text = _textTheme(c, googleFonts);
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
        primary: c.ink,
        onPrimary: c.bg,
        surface: c.bg,
        onSurface: c.ink,
      ),
      // Le fond vient de GlassBackdrop, posé par la transition de chaque page.
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: text,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: GlassPageTransitions(PredictiveBackPageTransitionsBuilder()),
          TargetPlatform.iOS: GlassPageTransitions(CupertinoPageTransitionsBuilder()),
          TargetPlatform.macOS: GlassPageTransitions(CupertinoPageTransitionsBuilder()),
          TargetPlatform.windows: GlassPageTransitions(ZoomPageTransitionsBuilder()),
          TargetPlatform.linux: GlassPageTransitions(ZoomPageTransitionsBuilder()),
          TargetPlatform.fuchsia: GlassPageTransitions(ZoomPageTransitionsBuilder()),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.bg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.ink3,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.bg,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: text.titleSmall,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.ink,
        refreshBackgroundColor: c.card,
      ),
    );
  }

  static TextTheme _textTheme(AppColors c, bool googleFonts) {
    TextStyle display(double size, {double height = 1.08, double spacing = -0.4}) {
      final style = TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: height,
        letterSpacing: spacing,
        color: c.ink,
      );
      return googleFonts ? GoogleFonts.bricolageGrotesque(textStyle: style) : style;
    }

    TextStyle body(double size, FontWeight weight, Color color, {double height = 1.4}) {
      final style = TextStyle(fontSize: size, fontWeight: weight, height: height, color: color);
      return googleFonts ? GoogleFonts.figtree(textStyle: style) : style;
    }

    return TextTheme(
      displaySmall: display(34, spacing: -0.9),
      headlineMedium: display(28, spacing: -0.6),
      headlineSmall: display(24, spacing: -0.4),
      titleLarge: display(21, spacing: -0.2),
      titleMedium: display(17, height: 1.12, spacing: -0.1),
      titleSmall: body(15, FontWeight.w700, c.ink),
      bodyLarge: body(16, FontWeight.w400, c.ink),
      bodyMedium: body(14.5, FontWeight.w400, c.ink2),
      bodySmall: body(12.5, FontWeight.w400, c.ink3),
      labelLarge: body(14, FontWeight.w600, c.ink),
      labelMedium: body(12.5, FontWeight.w600, c.ink3),
      labelSmall: body(11.5, FontWeight.w600, c.ink3),
    );
  }
}
