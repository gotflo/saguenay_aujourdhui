import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/live_sources.dart';
import '../assistant/plain_words.dart';
import '../../state/providers.dart';
import '../../state/web_relay.dart';
import '../../theme/colors.dart';
import '../../widgets/sheet_parts.dart';

Future<void> showDetailSheet(BuildContext context, SignalKind kind) =>
    showAppSheet<void>(context, (_) => DetailSheet(kind: kind));

class DetailSheet extends ConsumerWidget {
  const DetailSheet({super.key, required this.kind});

  final SignalKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider);
    final city = ref.watch(cityProvider);
    final now = ref.watch(nowProvider);
    if (place == null) return const SizedBox.shrink();

    return switch (kind) {
      SignalKind.bus => _BusDetails(place: place, now: now, live: city.transit),
      SignalKind.emergency => _EmergencyDetails(
        status: ref.watch(emergenciesProvider).value,
        now: ref.watch(clockProvider)(),
      ),
      SignalKind.water => _WaterDetails(
        city: city,
        now: now,
        takenAt: ref.watch(demoTimeProvider) != null
            ? null
            : ref.watch(waterLayerProvider).value?.snapshot?.takenAt,
      ),
      SignalKind.weather => _WeatherDetails(
        weather: city.weather,
        origin: ref.watch(demoTimeProvider) != null
            ? null
            : ref.watch(weatherProvider).value?.origin,
        now: now,
      ),
      SignalKind.power => _PowerDetails(
        place: place,
        power: city.power,
        origin: ref.watch(demoTimeProvider) != null ? null : ref.watch(powerProvider).value?.origin,
        now: now,
      ),
      SignalKind.collection => _CollectionDetails(place: place, now: now),
      SignalKind.parking => const _ParkingDetails(),
      SignalKind.roadwork => _RoadworkDetails(place: place, now: now),
      SignalKind.roads => _RoadsDetails(place: place, report: city.roads, now: now),
    };
  }
}

class _BusDetails extends StatelessWidget {
  const _BusDetails({required this.place, required this.now, this.live});

  final Place place;
  final DateTime now;
  final TransitRealtime? live;

  /// « dans 12 min · 2 min de retard », quand la STS donne le temps réel.
  String _when(Departure d) {
    final rt = live;
    final delay = rt != null && rt.isFreshAt(now) ? rt.delayFor(d) : null;
    final shift = delay == null ? 0 : (delay / 60).round();
    final base = inMinutes(d.minute + shift - minuteOfDay(now));
    if (delay == null) return base;
    if (shift >= 1) return '$base · $shift min de retard';
    if (shift <= -1) return '$base · ${-shift} min d’avance';
    return '$base · à l’heure';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final stop = place.stop;
    if (stop == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader('Bus', subtitle: 'Aucun arrêt favori pour cette adresse.'),
          SheetNote(
            'Dans la démo, seul le 201, rue Racine Est a un arrêt favori : le 150, Racine Est.',
          ),
        ],
      );
    }

    final departures = stop.after(now, count: 8);
    final day = switch (now.weekday) {
      DateTime.saturday => 'samedi',
      DateTime.sunday => 'dimanche',
      _ => 'jour de semaine',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader('Arrêt ${stop.name}', subtitle: 'Horaire de la STS, $day'),
        if (departures == null)
          SheetNote(
            'L’horaire couvre du ${shortDate(stop.validFrom)} au ${shortDate(stop.validTo)}.',
          )
        else if (departures.isEmpty)
          const SheetNote('Plus de départ aujourd’hui à cet arrêt.')
        else
          for (final d in departures)
            SheetRow(
              leading: Container(
                constraints: const BoxConstraints(minWidth: 40),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: c.blue, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  d.route,
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: d.headsign,
              subtitle: _when(d),
              trailing: Text(clockTime(d.minute), style: text.titleMedium),
            ),
        SheetNote(
          live != null && live!.isFreshAt(now)
              ? 'Horaire de la STS, avec les retards en direct.'
              : 'Horaire prévu de la STS. Le temps réel s’affiche quand le téléphone a du réseau.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () =>
              launchUrl(Uri.parse('https://transitapp.com/'), mode: LaunchMode.externalApplication),
          child: const Text('Planifier un trajet dans Transit'),
        ),
      ],
    );
  }
}

class _EmergencyDetails extends StatelessWidget {
  const _EmergencyDetails({required this.status, required this.now});

  final EmergencyStatus? status;
  final DateTime now;

  String _subtitle(EmergencyStatus st, EmergencySnapshot s) {
    final when = '${longDate(s.takenAt)} à ${clockTimeOf(s.takenAt)}';
    return switch (st.origin) {
      SourceOrigin.live when s.isStaleAt(now) =>
        'Relevé du $when. Le ministère n’a rien publié depuis.',
      SourceOrigin.live => 'En direct du ministère, relevé de ${clockTimeOf(s.takenAt)}',
      SourceOrigin.cached => 'Dernier relevé gardé sur le téléphone : $when',
      SourceOrigin.demo || SourceOrigin.none => 'Relevé du $when, pour la démo',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final st = status;
    final s = st?.snapshot;
    if (st == null || s == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader('Urgences', subtitle: 'Lecture du relevé du ministère…'),
          SizedBox(height: 12),
          LinearProgressIndicator(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader('Urgences', subtitle: _subtitle(st, s)),
        for (final room in s.rooms)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hôpital de ${room.hospital}', style: text.titleSmall),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ((room.occupancyPercent ?? 0) / 100).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    color: c.violet,
                    backgroundColor: c.bg,
                  ),
                ),
                const SizedBox(height: 8),
                // Les deux chiffres se mettent l'un sous l'autre quand la place manque.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    Text(
                      room.occupancyPercent == null
                          ? 'Civières : pas d’information'
                          : '${room.occupied} civières sur ${room.functional} (${room.occupancyPercent} %)',
                      style: text.bodySmall?.copyWith(color: c.ink2),
                    ),
                    if (room.waiting != null)
                      Text(
                        '${room.waiting} en attente',
                        style: text.bodySmall?.copyWith(color: c.ink2),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (st.origin == SourceOrigin.demo && kIsWeb && webRelay == null)
          const SheetNote(
            'Dans un navigateur, l’app ne peut pas lire le fichier du ministère. '
            'Sur le téléphone, ces chiffres se mettent à jour chaque heure.',
          ),
        const SheetNote(
          'Ces chiffres ne disent rien du triage ni du personnel sur place. '
          'Ne choisis pas un hôpital d’après eux.\n\nUrgence : 911. Conseil santé : 811.',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Source : ministère de la Santé et des Services sociaux, Données Québec (CC BY 4.0).',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _WaterDetails extends StatelessWidget {
  const _WaterDetails({required this.city, required this.now, this.takenAt});

  final CityData city;
  final DateTime now;

  /// Heure du relevé de la carte de la Ville ; `null` en démo.
  final DateTime? takenAt;

  @override
  Widget build(BuildContext context) {
    final byState = <NoticeState, List<WaterNotice>>{};
    for (final n in city.waterNotices) {
      byState.putIfAbsent(n.stateAt(now, knownUntil: city.waterKnownUntil), () => []).add(n);
    }
    final active = byState[NoticeState.active] ?? const [];
    final upcoming = byState[NoticeState.upcoming] ?? const [];
    final ended = byState[NoticeState.ended] ?? const [];
    final unknown = byState[NoticeState.unknown] ?? const [];

    Widget row(WaterNotice n) => SheetRow(
      title: n.type.label,
      subtitle: n.zone,
      trailing: Text(n.number, style: Theme.of(context).textTheme.bodySmall),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader(
          'Eau',
          subtitle: takenAt == null
              ? 'Avis de la Ville pour tout Saguenay'
              : 'Carte des avis de la Ville, relevé ${takenLabel(takenAt!, now)}',
        ),
        if (active.isEmpty && upcoming.isEmpty) const SheetNote('Aucun avis en cours ni à venir.'),
        if (active.isNotEmpty) ...[const SectionLabel('En cours'), for (final n in active) row(n)],
        if (upcoming.isNotEmpty) ...[
          const SectionLabel('À venir'),
          for (final n in upcoming) row(n),
        ],
        if (ended.isNotEmpty)
          SheetNote(
            '${ended.length} autres avis sont encore marqués « actifs » sur la carte de la Ville, '
            'mais leur date de fin est passée. L’app ne les montre plus.',
          ),
        if (unknown.isNotEmpty)
          SheetNote(
            'Le relevé date du 25 octobre. On ne sait pas si l’avis ${unknown.first.number} '
            'est levé à cette date.',
          ),
      ],
    );
  }
}

class _CollectionDetails extends StatelessWidget {
  const _CollectionDetails({required this.place, required this.now});

  final Place place;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final upcoming = place.collection.upcoming(now, count: 5);
    String when(DateTime day) {
      if (sameDay(day, now)) return 'aujourd’hui';
      if (sameDay(day, addDays(now, 1))) return 'demain';
      return '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader('Collectes', subtitle: place.label),
        if (upcoming.isEmpty)
          const SheetNote('Le calendrier de l’an prochain n’est pas encore publié par la Ville.')
        else
          for (final p in upcoming)
            SheetRow(
              title: p.streams.map((s) => s.label).join(' et '),
              subtitle: when(p.day).isEmpty ? null : when(p.day),
              trailing: Text(capitalize(shortDate(p.day)), style: text.titleSmall),
            ),
        const SheetNote('Le bac va au chemin la veille et se rentre avant midi.'),
        if (place.collectionIsExample)
          const SheetNote('Calendrier inventé pour cette adresse de démo.')
        else if (place.id.startsWith('adr:'))
          SheetNote(
            place.collectionMissing
                ? 'L’horaire de la Ville pour ton adresse arrive dès que le téléphone a du réseau.'
                : 'Horaire de la Ville pour ton adresse, relu chaque semaine. Les décalages des jours fériés y sont repris.',
          ),
      ],
    );
  }
}

class _ParkingDetails extends StatelessWidget {
  const _ParkingDetails();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeader('Stationnement de nuit', subtitle: 'Règlement de la Ville'),
        SheetRow(
          title: 'Quand',
          subtitle: 'Toutes les nuits',
          trailing: Text('15 nov. au 1er avril', style: text.titleSmall),
        ),
        SheetRow(
          title: 'Heures',
          subtitle: 'Rues et stationnements publics',
          trailing: Text('0 h à 7 h', style: text.titleSmall),
        ),
        SheetRow(
          title: 'Amende',
          subtitle: '30 \$ plus 15 \$ de frais',
          trailing: Text('${WinterParking.fine} \$', style: text.titleSmall),
        ),
        const SheetNote(
          'Sur certains tronçons commerciaux du centre-ville, l’interdiction commence seulement à 3 h. '
          'En attendant la liste exacte, l’app rappelle minuit partout.',
        ),
      ],
    );
  }
}

class _RoadworkDetails extends StatelessWidget {
  const _RoadworkDetails({required this.place, required this.now});

  final Place place;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final works = place.roadworks.where((w) => !w.work.isOverAt(now)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeader('Travaux', subtitle: 'Près de chez toi'),
        if (works.isEmpty)
          const SheetNote('Aucuns travaux près de chez toi.')
        else
          for (final w in works)
            SheetRow(
              title: '${w.work.street}, ${w.work.status}',
              subtitle: w.onMyStreet
                  ? w.work.details
                  : 'Dans ton arrondissement. ${w.work.details}',
            ),
      ],
    );
  }
}

class _WeatherDetails extends StatelessWidget {
  const _WeatherDetails({required this.weather, required this.origin, required this.now});

  final WeatherSnapshot? weather;

  /// `null` en démo.
  final SourceOrigin? origin;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final w = weather;
    if (w == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeader('Météo', subtitle: 'Environnement Canada'),
          SheetNote(
            origin == null
                ? 'Pas de météo pour ce moment de la démo.'
                : 'La météo arrive dès que le téléphone a du réseau.',
          ),
        ],
      );
    }
    final alerts = w.alerts.where((a) => a.activeAt(now)).toList();
    final subtitle = switch (origin) {
      SourceOrigin.cached => 'Hors ligne : relevé ${takenLabel(w.takenAt, now)}',
      null => 'Mise en situation pour la démo',
      _ => 'Saguenay, relevé ${takenLabel(w.takenAt, now)}',
    };
    final temperature = w.temperature;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader('Météo', subtitle: subtitle),
        if (temperature != null)
          SheetRow(
            title: w.condition ?? 'En ce moment',
            trailing: Text(temperatureLabel(temperature), style: text.headlineSmall),
          ),
        if (w.snowTonightCm case final cm? when cm > 0)
          SheetRow(
            title: 'Neige ce soir et cette nuit',
            trailing: Text('$cm cm', style: text.titleMedium),
          ),
        if (alerts.isNotEmpty) ...[
          const SectionLabel('Alertes'),
          for (final a in alerts) SheetRow(title: a.name, subtitle: [?a.what, ?a.when].join(' ')),
          PlainWords(
            [
              for (final a in alerts) [a.name, ?a.what, ?a.when].join('. '),
            ].join('\n'),
          ),
        ] else
          const SheetNote('Aucune alerte pour ton secteur.'),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Source : Environnement et Changement climatique Canada.',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _PowerDetails extends StatelessWidget {
  const _PowerDetails({
    required this.place,
    required this.power,
    required this.origin,
    required this.now,
  });

  final Place place;
  final PowerSnapshot? power;
  final SourceOrigin? origin;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = power;
    final lat = place.lat, lon = place.lon;
    final near = p == null || lat == null || lon == null
        ? const <PowerOutage>[]
        : p.near(lat, lon).where((o) => o.end == null || now.isBefore(o.end!)).toList();
    final current = near.where((o) => !o.planned).toList();
    final planned = near.where((o) => o.planned).toList();

    String hours(PowerOutage o) {
      final end = o.end;
      final day = sameDay(o.start, now) ? '' : '${capitalize(shortDate(o.start))}, ';
      return end == null
          ? '${day}depuis ${clockTimeOf(o.start)}'
          : '${day}de ${clockTimeOf(o.start)} à ${clockTimeOf(end)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader(
          'Électricité',
          subtitle: switch (origin) {
            _ when p == null => 'Hydro-Québec',
            SourceOrigin.cached => 'Hors ligne : relevé ${takenLabel(p.takenAt, now)}',
            null => 'Mise en situation pour la démo',
            _ => 'Hydro-Québec, relevé ${takenLabel(p.takenAt, now)}',
          },
        ),
        if (p == null)
          SheetNote(
            kIsWeb && webRelay == null
                ? 'Dans un navigateur, l’app ne peut pas lire les données d’Hydro-Québec. '
                      'Sur le téléphone, elles se mettent à jour toutes les dix minutes.'
                : 'Les pannes arrivent dès que le téléphone a du réseau.',
          )
        else if (near.isEmpty)
          const SheetNote('Aucune panne ni coupure planifiée dans ton secteur.'),
        if (current.isNotEmpty) ...[
          const SectionLabel('En cours'),
          for (final o in current)
            SheetRow(
              title: '${o.customers} client${o.customers > 1 ? 's' : ''} sans courant',
              subtitle: [hours(o), if (o.cause != null) o.cause!].join(' · '),
            ),
        ],
        if (planned.isNotEmpty) ...[
          const SectionLabel('Planifiées'),
          for (final o in planned) SheetRow(title: 'Travaux d’Hydro-Québec', subtitle: hours(o)),
        ],
        const SheetNote(
          'Le secteur d’une panne est approximatif : Hydro-Québec donne un point, pas les rues touchées.',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Source : Hydro-Québec (CC BY-NC 4.0).', style: text.bodySmall),
        ),
      ],
    );
  }
}

class _RoadsDetails extends StatelessWidget {
  const _RoadsDetails({required this.place, required this.report, required this.now});

  final Place place;
  final RoadReport? report;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final r = report;
    if (r == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader('Routes', subtitle: 'Ministère des Transports'),
          SheetNote('L’état des routes arrive dès que le téléphone a du réseau.'),
        ],
      );
    }
    final lat = place.lat ?? WeatherClient.saguenay.lat,
        lon = place.lon ?? WeatherClient.saguenay.lon;
    final cameras = r.camerasNear(lat, lon);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader(
          'Routes',
          subtitle: 'État de la chaussée, relevé ${takenLabel(r.takenAt, now)}',
        ),
        for (final s in r.segments.take(12))
          SheetRow(
            leading: Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: s.isNormal ? c.bg : c.stone.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${s.route}', textAlign: TextAlign.center, style: text.labelLarge),
            ),
            title: '${s.from} → ${s.to}',
            subtitle: '${s.surface} · visibilité ${s.visibility.toLowerCase()}',
          ),
        if (cameras.isNotEmpty) ...[
          const SectionLabel('Caméras près de chez toi'),
          for (final cam in cameras)
            SheetRow(
              title: cam.place,
              trailing: TextButton(
                onPressed: () =>
                    launchUrl(Uri.parse(cam.url), mode: LaunchMode.externalApplication),
                child: const Text('Voir'),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Source : ministère des Transports et de la Mobilité durable, Québec 511 (CC BY 4.0).',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}
