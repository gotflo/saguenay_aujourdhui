import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Ouvre une feuille du bas en verre dépoli, aux couleurs de l'app.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (context) {
      final c = context.colors;
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.sheet,
              border: Border(top: BorderSide(color: c.glassEdge)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .86),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: c.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        22,
                        6,
                        22,
                        28 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: builder(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class SheetHeader extends StatelessWidget {
  const SheetHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Une ligne « libellé à gauche, valeur à droite ».
class SheetRow extends StatelessWidget {
  const SheetRow({super.key, required this.title, this.subtitle, this.trailing, this.leading});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.labelLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            // Une valeur longue passe à la ligne au lieu de pousser le libellé.
            Flexible(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: DefaultTextStyle.merge(textAlign: TextAlign.end, child: trailing!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SheetNote extends StatelessWidget {
  const SheetNote(this.text, {super.key, this.tone});

  final String text;

  /// Couleur de fond, par défaut le fond de l'app.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: tone ?? c.bg, borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.ink2)),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 2),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
