import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../../state/live_sources.dart';
import '../../state/providers.dart';
import '../../state/web_relay.dart';
import '../../theme/colors.dart';
import '../../theme/kind_style.dart';
import '../../widgets/sheet_parts.dart';

Future<void> showSourcesSheet(BuildContext context) =>
    showAppSheet<void>(context, (_) => const SourcesSheet());

/// D'où vient chaque information, si elle est à jour, et si elle marche sans réseau.
class SourcesSheet extends ConsumerWidget {
  const SourcesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final place = ref.watch(savedPlaceProvider);
    final demoPlace = place != null && !place.id.startsWith('adr:');

    String live<T>(LiveStatus<T>? status, DateTime? Function(T) takenAt, {bool web = true}) {
      if (status == null) return 'lecture en cours…';
      final snapshot = status.snapshot;
      final at = snapshot == null ? null : takenAt(snapshot);
      final when = at == null ? '' : ' ${takenLabel(at, now)}';
      return switch (status.origin) {
        SourceOrigin.live => 'en direct, relevé$when',
        SourceOrigin.cached => 'hors ligne : dernier relevé$when',
        SourceOrigin.demo =>
          kIsWeb && !web ? 'sur le téléphone seulement' : 'relevé de démonstration',
        SourceOrigin.none =>
          kIsWeb && !web ? 'sur le téléphone seulement' : 'pas de réseau pour l’instant',
      };
    }

    final rows = <(SignalKind, String, String, String)>[
      (
        SignalKind.collection,
        'Collectes',
        'Ville de Saguenay',
        demoPlace
            ? 'relevé du 25 octobre pour cette adresse de démo'
            : kIsWeb && webRelay == null
            ? 'sur le téléphone seulement'
            : 'horaire de ton adresse, relu chaque semaine',
      ),
      (
        SignalKind.parking,
        'Stationnement de nuit',
        'Règlement de la Ville',
        'calculé sur le téléphone',
      ),
      (
        SignalKind.water,
        'Avis d’eau',
        'Carte des avis de la Ville',
        live<WaterSnapshot>(ref.watch(waterLayerProvider).value, (w) => w.takenAt),
      ),
      (
        SignalKind.roadwork,
        'Travaux',
        'Carte de la circulation de la Ville',
        live<RoadworkSnapshot>(ref.watch(roadworksLayerProvider).value, (w) => w.takenAt),
      ),
      (
        SignalKind.bus,
        'Bus',
        'Société de transport du Saguenay',
        kIsWeb ? 'horaire prévu ; le temps réel sur le téléphone' : 'horaire et retards en direct',
      ),
      (
        SignalKind.weather,
        'Météo',
        'Environnement Canada',
        live<WeatherSnapshot>(ref.watch(weatherProvider).value, (w) => w.takenAt),
      ),
      (
        SignalKind.power,
        'Électricité',
        'Hydro-Québec',
        live<PowerSnapshot>(
          ref.watch(powerProvider).value,
          (p) => p.takenAt,
          web: webRelay != null,
        ),
      ),
      (
        SignalKind.roads,
        'Routes',
        'Ministère des Transports',
        live<RoadReport>(ref.watch(roadsProvider).value, (r) => r.takenAt),
      ),
      (
        SignalKind.emergency,
        'Urgences',
        'Ministère de la Santé',
        live<EmergencySnapshot>(
          ref.watch(emergenciesProvider).value,
          (e) => e.takenAt,
          web: webRelay != null,
        ),
      ),
    ];

    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeader(
          'Neuf sources, une seule app',
          subtitle: 'Avant, il fallait les consulter une par une.',
        ),
        for (final (kind, title, source, state) in rows)
          SheetRow(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kind.color(c).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(kind.icon, size: 19, color: kind.color(c)),
            ),
            title: title,
            subtitle: '$source · $state',
          ),
        const SheetNote(
          'Ce qui est calculé sur le téléphone marche sans réseau, et le widget aussi : il connaît '
          'déjà les sept prochains jours. Les sources en direct ont besoin du réseau ; sans lui, '
          'l’app montre le dernier relevé et le dit.',
        ),
        const SheetNote(
          'La Ville et la STS publient ces données sur leurs sites publics ; l’app les lit de la même '
          'façon. Leur accord est demandé avant la sortie publique.',
        ),
        const SheetNote(
          'Licences : Données Québec, ministère de la Santé et ministère des Transports (CC BY 4.0), '
          'Environnement Canada (Licence du gouvernement ouvert), Hydro-Québec (CC BY-NC 4.0).',
        ),
      ],
    );
  }
}
