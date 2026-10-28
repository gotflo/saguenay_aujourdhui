import 'package:flutter/material.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../../theme/colors.dart';
import '../../theme/kind_style.dart';
import '../../widgets/pressable.dart';
import '../../widgets/glass.dart';

/// La grande carte du haut : la chose la plus importante à cette heure-ci.
class HeroCard extends StatefulWidget {
  const HeroCard({super.key, required this.signal, this.onTap});

  final Signal? signal;

  /// Ouvre la fiche de l'information affichée.
  final VoidCallback? onTap;

  @override
  State<HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<HeroCard> {
  bool _showWhy = false;

  @override
  void didUpdateWidget(HeroCard old) {
    super.didUpdateWidget(old);
    // Le titre du bus change chaque minute : on ne referme « Pourquoi » que
    // si c'est une autre information.
    if (old.signal?.kind != widget.signal?.kind) _showWhy = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final s = widget.signal;
    final (bg, fg) = switch (s) {
      // Quand rien ne presse, la carte du haut est en verre comme les autres.
      null => (Colors.transparent, c.ink),
      Signal(critical: true) => (c.critical, Colors.white),
      _ => (c.accent, c.onAccent),
    };
    // Sur une alerte, le texte reste plein pour garder le contraste.
    final soft = s?.critical == true ? fg : fg.withValues(alpha: .82);

    final card = Container(
      key: ValueKey(s?.kind ?? 'calme'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(s?.kind.icon ?? Icons.wb_sunny_rounded, size: 18, color: soft),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s?.label ?? 'Aujourd’hui',
                  style: text.labelLarge?.copyWith(color: soft, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s?.title ?? 'Rien de spécial pour l’instant',
            style: text.headlineSmall?.copyWith(color: fg),
          ),
          const SizedBox(height: 6),
          Text(
            s?.body ?? 'On te fait signe si quelque chose change.',
            style: text.bodyMedium?.copyWith(color: soft),
          ),
          if (s != null && s.why.isNotEmpty) ...[
            const SizedBox(height: 14),
            Pressable(
              onTap: () => setState(() => _showWhy = !_showWhy),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _showWhy ? 'Fermer' : 'Pourquoi je vois ça ?',
                  style: text.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: _showWhy
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(s.why, style: text.bodyMedium?.copyWith(color: soft)),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ],
      ),
    );

    // Annoncé tout haut seulement pour une alerte de santé : un compte à
    // rebours lu chaque minute deviendrait vite pénible.
    final switcher = Semantics(
      liveRegion: s?.critical == true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: .97, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: s == null ? Glass(key: card.key, radius: 28, child: card) : card,
      ),
    );
    final onTap = widget.onTap;
    if (s == null || onTap == null) return switcher;
    return Pressable(onTap: onTap, child: switcher);
  }
}
