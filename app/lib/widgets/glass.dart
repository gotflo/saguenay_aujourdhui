import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Une surface de verre dépoli : un peu de flou sur ce qui passe dessous, un
/// voile clair et un liseré lumineux. Le texte reste aussi lisible que sur
/// une carte pleine (voir le test de contraste).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding,
    this.circle = false,
    this.tint,
    this.blur = 18,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool circle;

  /// Remplace le voile, pour une surface teintée (une puce choisie, par exemple).
  final Color? tint;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = circle ? BoxShape.circle : BoxShape.rectangle;
    final corners = circle ? null : BorderRadius.circular(radius);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? c.glass,
        shape: shape,
        borderRadius: corners,
        border: Border.all(color: c.glassEdge),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    final frosted = BackdropFilter.grouped(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: surface,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: corners,
        boxShadow: [BoxShadow(color: c.glassShadow, blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: circle ? ClipOval(child: frosted) : ClipRRect(borderRadius: corners!, child: frosted),
    );
  }
}

/// Le fond des écrans : la couleur de l'app et deux grands halos, chaud en
/// haut, frais en bas, que le verre laisse deviner. De simples dégradés : rien
/// à recalculer pendant le défilement.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.bg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1.1, -1.05),
            radius: 1.25,
            colors: [c.haloWarm, c.haloWarm.withValues(alpha: 0)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.2, 0.85),
              radius: 1.1,
              colors: [c.haloCool, c.haloCool.withValues(alpha: 0)],
            ),
          ),
          // Toutes les surfaces de verre de l'écran partagent un seul calque de flou.
          child: BackdropGroup(child: child),
        ),
      ),
    );
  }
}

/// La transition d'origine de chaque plateforme, avec le fond à halos sous la
/// page : il bouge avec elle et reste opaque pendant l'animation.
class GlassPageTransitions extends PageTransitionsBuilder {
  const GlassPageTransitions(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    GlassBackdrop(child: child),
  );
}
