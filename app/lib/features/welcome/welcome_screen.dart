import 'package:flutter/material.dart';

import 'package:saguenay_core/saguenay_core.dart';

import '../../theme/colors.dart';
import '../../theme/kind_style.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/logo.dart';
import '../places/place_picker.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _maxWidth = 620.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final top = MediaQuery.paddingOf(context).top;

    Widget column(Widget child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: child,
      ),
    );

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: c.accent,
            padding: EdgeInsets.fromLTRB(24, top + 32, 24, 36),
            child: column(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Logo(size: 64),
                  const SizedBox(height: 28),
                  Text(
                    'Ta journée à Saguenay, d’un coup d’œil.',
                    style: text.displaySmall?.copyWith(color: c.onAccent),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Le bac à sortir, le stationnement de nuit, les avis d’eau, le prochain bus. '
                    'Seulement ce qui te concerne, au moment où ça compte.',
                    style: text.bodyLarge?.copyWith(color: c.onAccent.withValues(alpha: .78)),
                  ),
                  const SizedBox(height: 22),
                  const _Sources(),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
            child: column(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choisis ton adresse', style: text.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'N’importe quelle adresse de Saguenay. Elle reste sur ton téléphone.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  const FadeIn(index: 1, child: AddressSearch(onCard: false)),
                  const SizedBox(height: 22),
                  Text(
                    'Ou essaie une adresse de démo',
                    style: text.labelLarge?.copyWith(color: c.ink3),
                  ),
                  const SizedBox(height: 10),
                  const FadeIn(index: 2, child: PlaceList(onCard: false)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le problème en une image : les endroits à surveiller, réunis ici.
class _Sources extends StatelessWidget {
  const _Sources();

  static const _kinds = [
    (SignalKind.collection, 'Collectes'),
    (SignalKind.parking, 'Stationnement'),
    (SignalKind.water, 'Eau'),
    (SignalKind.weather, 'Météo'),
    (SignalKind.power, 'Électricité'),
    (SignalKind.roads, 'Routes'),
    (SignalKind.roadwork, 'Travaux'),
    (SignalKind.bus, 'Bus'),
    (SignalKind.emergency, 'Urgences'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (kind, label) in _kinds)
              Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                decoration: BoxDecoration(
                  color: c.onAccent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kind.icon, size: 14, color: c.onAccent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        style: text.labelMedium?.copyWith(color: c.onAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Une douzaine de sources qu’il fallait consulter une par une. Ici, une seule.',
          style: text.bodySmall?.copyWith(color: c.onAccent.withValues(alpha: .78)),
        ),
      ],
    );
  }
}
