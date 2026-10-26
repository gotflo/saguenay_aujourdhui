import 'calendar.dart';
import 'collection.dart';
import 'emergency.dart';
import 'format.dart';
import 'parking.dart';
import 'place.dart';
import 'power.dart';
import 'roads.dart';
import 'signal.dart';
import 'transit.dart';
import 'water.dart';
import 'weather.dart';

/// Ce que la ville publie pour tout le monde, peu importe l'adresse.
class CityData {
  const CityData({
    this.waterNotices = const [],
    this.waterKnownUntil,
    this.emergencies,
    this.weather,
    this.power,
    this.roads,
    this.transit,
  });

  final List<WaterNotice> waterNotices;

  /// Jusqu'où on peut se fier aux avis « jusqu'à nouvel ordre ».
  final DateTime? waterKnownUntil;
  final EmergencySnapshot? emergencies;
  final WeatherSnapshot? weather;
  final PowerSnapshot? power;
  final RoadReport? roads;

  /// Retards et avances des bus, en direct.
  final TransitRealtime? transit;
}

class Today {
  const Today({required this.hero, required this.signals, required this.tiles});

  /// La carte du haut, ou `null` quand rien ne mérite d'être mis en avant.
  final Signal? hero;

  /// Tout ce qui est pertinent, du plus important au moins important.
  final List<Signal> signals;

  /// Ce qui s'affiche sous la carte du haut.
  final List<Tile> tiles;
}

class TimelineEntry {
  const TimelineEntry(this.at, this.today);

  final DateTime at;
  final Today today;

  Map<String, Object?> toJson() {
    final hero = today.hero;
    final second = today.tiles.where((t) => !t.quiet).firstOrNull;
    return {
      'at': at.millisecondsSinceEpoch,
      'kind': hero?.kind.name,
      'label': hero?.label ?? 'Aujourd’hui',
      'title': hero?.title ?? 'Rien de spécial',
      'body': hero?.body ?? 'On te fait signe si quelque chose change.',
      'critical': hero?.critical ?? false,
      'second': second == null ? null : '${second.label} · ${second.value}',
      'secondDetail': second?.detail,
      'secondKind': second?.kind.name,
    };
  }

  /// Ce que le widget affiche, sans l'heure : deux entrées au même contenu se confondent.
  String get contentKey {
    final json = toJson()..remove('at');
    return json.values.join('\u0001');
  }
}

/// Décide quoi montrer, et dans quel ordre.
///
/// Chaque information a un poids (son importance en soi) et une urgence
/// (à quel point c'est le moment). Le score est le produit des deux. Pas de
/// modèle opaque : chaque règle tient en quelques lignes et se teste.
class RelevanceEngine {
  const RelevanceEngine({this.parking = const WinterParking(), this.heroThreshold = 15});

  final WinterParking parking;

  /// Sous ce score, une information reste dans l'app sans prendre la carte du haut.
  final int heroThreshold;

  /// Avec [fixedTimes], les textes ne disent jamais « dans 16 min » mais « à
  /// 7 h 46 » : ils restent vrais tant que l'information ne change pas. C'est
  /// ce qu'il faut au widget, qui ne se redessine pas chaque minute.
  List<Signal> signals(Place place, CityData city, DateTime now, {bool fixedTimes = false}) {
    final out = <Signal>[
      ?_water(place, city, now),
      ?_weather(city, now),
      ?_power(place, city, now),
      ?_roads(city, now),
      ?_parking(now),
      ?_collection(place, now),
      ?_bus(place, now, fixedTimes: fixedTimes, live: fixedTimes ? null : city.transit),
      ..._roadworks(place, now),
    ];
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  Today today(Place place, CityData city, DateTime now, {bool fixedTimes = false}) {
    final all = signals(place, city, now, fixedTimes: fixedTimes);
    final weather = city.weather;
    final temperature = weather?.temperature;
    final hero = all.isNotEmpty && all.first.score >= heroThreshold ? all.first : null;
    return Today(
      hero: hero,
      signals: all,
      tiles: [
        for (final s in all)
          if (!identical(s, hero)) s.tile,
        if (!all.any((s) => s.kind == SignalKind.water))
          const Tile(
            kind: SignalKind.water,
            label: 'Eau',
            value: 'Rien à signaler',
            detail: 'à ton adresse',
            quiet: true,
          ),
        if (weather != null &&
            temperature != null &&
            !weather.isStaleAt(now) &&
            !all.any((s) => s.kind == SignalKind.weather))
          Tile(
            kind: SignalKind.weather,
            label: 'Météo',
            value: temperatureLabel(temperature),
            detail: weather.condition?.toLowerCase() ?? 'à Saguenay',
            quiet: true,
          ),
        ?_roadsTile(city, now, all),
        if (place.collectionMissing)
          Tile(
            kind: SignalKind.collection,
            label: 'Collecte',
            value: 'Horaire à venir',
            detail: place.collectionMissingNote ?? 'dès que le réseau revient',
            quiet: true,
          ),
        const Tile(
          kind: SignalKind.emergency,
          label: 'Urgences',
          value: 'Voir l’achalandage',
          detail: 'Chicoutimi, Jonquière, La Baie',
          quiet: true,
        ),
      ],
    );
  }

  /// Ce que le widget affichera dans les prochains jours, une entrée par changement.
  ///
  /// Le widget d'écran d'accueil est du code natif : il ne peut pas faire
  /// tourner ce moteur. L'app calcule donc la suite à l'avance et le widget
  /// n'a qu'à prendre la bonne entrée selon l'heure.
  ///
  /// On sonde aux [stepMinutes] ; quand le contenu change entre deux sondes,
  /// on repasse minute par minute pour trouver le moment exact. Le bus de
  /// 7 h 46 disparaît donc à 7 h 47, pas à 7 h 50.
  List<TimelineEntry> timeline(
    Place place,
    CityData city,
    DateTime from, {
    Duration span = const Duration(days: 7),
    int stepMinutes = 5,
  }) {
    // Par soustraction plutôt qu'avec le constructeur : la nuit du passage à
    // l'heure normale, 1 h 45 existe deux fois et le constructeur prend la première.
    final start = from.subtract(
      Duration(
        seconds: from.second,
        milliseconds: from.millisecond,
        microseconds: from.microsecond,
      ),
    );
    final end = start.add(span);
    final out = <TimelineEntry>[];
    TimelineEntry entryAt(DateTime t) => TimelineEntry(t, today(place, city, t, fixedTimes: true));
    void keep(TimelineEntry e) {
      if (out.isEmpty || out.last.contentKey != e.contentKey) out.add(e);
    }

    keep(entryAt(start));
    var previous = start;
    var t = start.add(Duration(minutes: stepMinutes - start.minute % stepMinutes));
    while (t.isBefore(end)) {
      final probe = entryAt(t);
      if (probe.contentKey != out.last.contentKey) {
        for (
          var m = previous.add(const Duration(minutes: 1));
          m.isBefore(t);
          m = m.add(const Duration(minutes: 1))
        ) {
          keep(entryAt(m));
        }
        keep(probe);
      }
      previous = t;
      t = t.add(Duration(minutes: stepMinutes));
    }
    return out;
  }

  // Eau ----------------------------------------------------------------------

  /// Le plus sérieux des avis qui touchent l'adresse : une coupure annoncée
  /// ne doit pas cacher un avis d'ébullition en cours.
  Signal? _water(Place place, CityData city, DateTime now) {
    Signal? best;
    for (final number in place.waterNotices) {
      final notice = city.waterNotices.where((n) => n.number == number).firstOrNull;
      if (notice == null) continue;
      final s = _waterNotice(notice, city, now);
      if (s != null && (best == null || s.score > best.score)) best = s;
    }
    return best;
  }

  Signal? _waterNotice(WaterNotice notice, CityData city, DateTime now) {
    final state = notice.stateAt(now, knownUntil: city.waterKnownUntil);
    final boil = notice.type == WaterNoticeType.boil;
    final end = notice.end;

    if (state == NoticeState.active) {
      return Signal(
        kind: SignalKind.water,
        label: notice.type.label,
        title: boil ? 'Fais bouillir l’eau avant de la boire' : 'L’eau est coupée chez toi',
        body: boil
            ? 'Au moins une minute à gros bouillons. En vigueur depuis '
                  '${weekdayName(notice.start)}, ${clockTimeOf(notice.start)}.'
            : end == null
            ? 'Jusqu’à nouvel ordre.'
            : 'Jusqu’à ${clockTimeOf(end)}.',
        why:
            'Ton adresse est dans la zone de l’avis. C’est une question de santé, '
            'donc ça passe avant tout.',
        weight: 1,
        urgency: 1,
        critical: boil,
        notify: true,
        tile: Tile(
          kind: SignalKind.water,
          label: 'Eau',
          value: boil ? 'Fais bouillir l’eau' : 'Coupée',
          detail: 'avis ${notice.number}',
        ),
      );
    }
    if (state == NoticeState.upcoming &&
        notice.start.difference(now) <= const Duration(hours: 24)) {
      final when = sameDay(notice.start, now) ? 'Aujourd’hui' : 'Demain';
      final hours = end == null
          ? 'dès ${clockTimeOf(notice.start)}'
          : 'de ${clockTimeOf(notice.start)} à ${clockTimeOf(end)}';
      return Signal(
        kind: SignalKind.water,
        label: when,
        title: '${notice.type.label} $hours',
        body: notice.zone,
        why: 'Un avis touchera ton adresse dans moins de 24 heures.',
        weight: .8,
        urgency: .7,
        tile: Tile(
          kind: SignalKind.water,
          label: 'Eau',
          value: notice.type.label,
          detail: when.toLowerCase(),
        ),
      );
    }
    return null;
  }

  // Météo ------------------------------------------------------------------------

  Signal? _weather(CityData city, DateTime now) {
    final w = city.weather;
    if (w == null) return null;

    // Une alerte sans fin connue ne reste pas plus d'une journée.
    final alert = w.alerts
        .where((a) => a.activeAt(now) && now.isBefore(a.issuedAt.add(const Duration(hours: 24))))
        .firstOrNull;
    if (alert != null) {
      final end = alert.endsAt;
      return Signal(
        kind: SignalKind.weather,
        label: 'Météo',
        title: alert.name,
        body:
            alert.what ??
            (end == null
                ? 'Environnement Canada a émis une alerte pour ton secteur.'
                : 'Jusqu’à ${clockTimeOf(end)}${sameDay(end, now) ? '' : ' ${weekdayName(end)}'}.'),
        why: 'Environnement Canada a émis cette alerte pour ton secteur.',
        weight: alert.level.weight,
        urgency: alert.level.urgency,
        notify: alert.level == WeatherAlertLevel.warning,
        tile: Tile(
          kind: SignalKind.weather,
          label: 'Météo',
          value: alert.level.label,
          detail: alert.name.toLowerCase(),
        ),
      );
    }

    final snow = w.snowTonightCm;
    if (snow == null || snow < 5) return null;
    // La prévision « ce soir et cette nuit » vaut jusqu'au lendemain matin.
    final morning = _memo(
      w,
      'matin',
      () => atMinute(addDays(w.takenAt, w.takenAt.hour < 5 ? 0 : 1), 7 * 60),
    );
    if (now.isBefore(w.takenAt) || !now.isBefore(morning)) return null;
    final m = minuteOfDay(now);
    final carOff =
        _memo(parking, 'nuit ${_day(now)}', () => _ParkingDay(parking, now)).appliesTonight ||
        parking.inForceAt(now);
    return Signal(
      kind: SignalKind.weather,
      label: m < 7 * 60 ? 'Cette nuit' : 'Ce soir',
      title: 'Jusqu’à $snow cm de neige',
      body: carOff
          ? 'L’auto hors de la rue, et du temps pour déneiger demain matin.'
          : 'Prévois du temps pour déneiger demain matin.',
      why: 'Environnement Canada annonce de la neige pour ce soir et cette nuit.',
      weight: .7,
      urgency: m >= 17 * 60
          ? .9
          : m < 7 * 60
          ? .7
          : .5,
      tile: Tile(kind: SignalKind.weather, label: 'Neige', value: '$snow cm', detail: 'cette nuit'),
    );
  }

  // Électricité --------------------------------------------------------------------

  Signal? _power(Place place, CityData city, DateTime now) {
    final p = city.power;
    final lat = place.lat, lon = place.lon;
    if (p == null || lat == null || lon == null) return null;
    final near = _memo(p, 'secteur $lat,$lon', () => p.near(lat, lon).toList());

    final outage = near.where((o) => !o.planned && o.activeAt(now, takenAt: p.takenAt)).firstOrNull;
    if (outage != null) {
      final end = outage.end;
      final back = end == null
          ? null
          : '${clockTimeOf(end)}${sameDay(end, now) ? '' : ' ${weekdayName(end)}'}';
      final many = outage.customers > 1 ? 's' : '';
      return Signal(
        kind: SignalKind.power,
        label: 'Électricité',
        title: 'Panne dans ton secteur',
        body: back == null
            ? 'Hydro-Québec n’a pas encore d’heure de retour.'
            : 'Retour du courant prévu vers $back.',
        why:
            '${outage.customers} client$many privé$many de courant près de ton adresse'
            '${outage.cause == null ? '' : ' (${outage.cause})'}, selon Hydro-Québec.',
        weight: .75,
        urgency: 1,
        tile: Tile(
          kind: SignalKind.power,
          label: 'Électricité',
          value: 'Panne',
          detail: back == null ? 'retour à venir' : 'retour vers $back',
        ),
      );
    }

    final planned = near
        .where(
          (o) =>
              o.planned &&
              o.end != null &&
              now.isBefore(o.end!) &&
              o.start.difference(now) <= const Duration(hours: 48),
        )
        .firstOrNull;
    if (planned == null) return null;
    final end = planned.end!;
    final started = !now.isBefore(planned.start);
    final when = started
        ? 'En ce moment'
        : sameDay(planned.start, now)
        ? 'Aujourd’hui'
        : sameDay(planned.start, addDays(now, 1))
        ? 'Demain'
        : capitalize(weekdayName(planned.start));
    return Signal(
      kind: SignalKind.power,
      label: when,
      title: 'Courant coupé de ${clockTimeOf(planned.start)} à ${clockTimeOf(end)}',
      body: 'Travaux planifiés par Hydro-Québec dans ton secteur.',
      why: 'Hydro-Québec prévoit une interruption près de ton adresse.',
      weight: .7,
      urgency: started
          ? 1
          : planned.start.difference(now) <= const Duration(hours: 12)
          ? .8
          : .35,
      tile: Tile(
        kind: SignalKind.power,
        label: 'Électricité',
        value: started ? 'Coupée' : 'Coupure prévue',
        detail: started ? 'jusqu’à ${clockTimeOf(end)}' : when.toLowerCase(),
      ),
    );
  }

  // Routes ------------------------------------------------------------------------

  /// La carte du haut seulement pour une route fermée, glacée ou sans
  /// visibilité ; le reste se lit dans la tuile.
  Signal? _roads(CityData city, DateTime now) {
    final r = city.roads;
    final worst = r?.worst;
    if (r == null || r.isStaleAt(now) || worst == null || !worst.isSevere) return null;
    return Signal(
      kind: SignalKind.roads,
      label: 'Routes',
      title: 'Route ${worst.route} : ${worst.surface.toLowerCase()}',
      body: '${worst.from} → ${worst.to}. Visibilité ${worst.visibility.toLowerCase()}.',
      why: 'Le ministère des Transports signale une route difficile autour de Saguenay.',
      weight: .6,
      urgency: 1,
      tile: Tile(
        kind: SignalKind.roads,
        label: 'Route ${worst.route}',
        value: _capitalize(worst.surface),
        detail: 'visibilité ${worst.visibility.toLowerCase()}',
      ),
    );
  }

  Tile? _roadsTile(CityData city, DateTime now, List<Signal> all) {
    final r = city.roads;
    if (r == null || r.isStaleAt(now) || r.segments.isEmpty) return null;
    if (all.any((s) => s.kind == SignalKind.roads)) return null;
    final worst = r.worst;
    if (worst == null) {
      return const Tile(
        kind: SignalKind.roads,
        label: 'Routes',
        value: 'Dégagées',
        detail: '175, 170, 172',
        quiet: true,
      );
    }
    return Tile(
      kind: SignalKind.roads,
      label: 'Route ${worst.route}',
      value: _capitalize(worst.surface),
      detail: 'visibilité ${worst.visibility.toLowerCase()}',
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // Stationnement d'hiver ------------------------------------------------------

  Signal? _parking(DateTime now) {
    final m = minuteOfDay(now);

    if (parking.inForceAt(now)) {
      return const Signal(
        kind: SignalKind.parking,
        label: 'En ce moment',
        title: 'Stationnement interdit dans la rue',
        body: 'Jusqu’à 7 h, partout en ville.',
        why: 'C’est l’hiver : la règle s’applique toutes les nuits, de minuit à 7 h.',
        weight: .9,
        urgency: .7,
        tile: Tile(
          kind: SignalKind.parking,
          label: 'Stationnement',
          value: 'Interdit',
          detail: 'jusqu’à 7 h',
        ),
      );
    }

    final day = _memo(parking, 'nuit ${_day(now)}', () => _ParkingDay(parking, now));
    if (day.appliesTonight) {
      if (m >= 17 * 60) {
        final firstNight = !day.appliesToday;
        return Signal(
          kind: SignalKind.parking,
          label: 'Cette nuit',
          title: firstNight
              ? 'Première nuit sans auto dans la rue'
              : 'Pas d’auto dans la rue cette nuit',
          body: firstNight
              ? 'À partir de minuit, et chaque nuit jusqu’au 1er avril.'
              : 'Interdit de minuit à 7 h. L’amende est de ${WinterParking.fine} \$.',
          why:
              'La règle d’hiver s’applique toutes les nuits. Plus minuit approche, '
              'plus ce rappel passe en premier.',
          weight: .9,
          urgency: m >= 21 * 60
              ? 1
              : m >= 19 * 60
              ? .8
              : .55,
          tile: const Tile(
            kind: SignalKind.parking,
            label: 'Stationnement',
            value: 'Interdit dès minuit',
            detail: 'dans la rue',
          ),
        );
      }
      return const Signal(
        kind: SignalKind.parking,
        label: 'Ce soir',
        title: 'Interdit dans la rue dès minuit',
        body: 'Comme chaque nuit d’hiver.',
        why: 'Petit rappel pendant la journée. Il passera en premier ce soir.',
        weight: .9,
        urgency: .15,
        tile: Tile(
          kind: SignalKind.parking,
          label: 'Stationnement',
          value: 'Interdit dès minuit',
          detail: 'ce soir',
        ),
      );
    }

    final daysLeft = day.daysToSeason;
    if (daysLeft > 0 && daysLeft <= 10) {
      return const Signal(
        kind: SignalKind.parking,
        label: 'Bientôt',
        title: 'Stationnement de nuit interdit dès le 15 novembre',
        body: 'De minuit à 7 h, jusqu’au 1er avril.',
        why: 'La saison approche, on prévient quelques jours avant.',
        weight: .5,
        urgency: .2,
        tile: Tile(
          kind: SignalKind.parking,
          label: 'Stationnement',
          value: 'Dès le 15 nov.',
          detail: 'la nuit',
        ),
      );
    }
    return null;
  }

  // Collectes ------------------------------------------------------------------

  Signal? _collection(Place place, DateTime now) {
    if (place.collectionMissing) return null;
    final day = _memo(
      place.collection,
      'collecte ${_day(now)}',
      () => _CollectionDay(place.collection, now),
    );
    final m = minuteOfDay(now);

    if (!day.coversToday || (!day.coversTomorrow && m >= 15 * 60)) {
      return _calendarPending(day.coversToday ? now.year + 1 : now.year);
    }

    final today = day.today;
    final next = day.tomorrow;

    if (today.isNotEmpty && m < 7 * 60) {
      return Signal(
        kind: SignalKind.collection,
        label: 'Ce matin',
        title: 'Le camion passe ce matin',
        body:
            '${capitalize(_bins(today))} ${today.length > 1 ? 'doivent' : 'doit'} être au chemin.',
        why: 'Ta collecte, c’est aujourd’hui.',
        weight: .65,
        urgency: 1,
        tile: Tile(
          kind: SignalKind.collection,
          label: 'Collecte',
          value: _labels(today),
          detail: 'ce matin',
        ),
      );
    }
    if (next.isNotEmpty && m >= 15 * 60) {
      return Signal(
        kind: SignalKind.collection,
        label: 'Ce soir',
        title: 'Sors ${_bins(next)}',
        body: 'La collecte passe demain matin.',
        why:
            'Ta collecte est demain, et le bac doit être au chemin la veille. '
            'Ce rappel monte en soirée.',
        weight: .65,
        urgency: m >= 19 * 60
            ? 1
            : m >= 17 * 60
            ? .8
            : .6,
        tile: Tile(
          kind: SignalKind.collection,
          label: 'Collecte',
          value: _labels(next),
          detail: 'demain matin',
        ),
      );
    }
    if (today.isNotEmpty && m < 12 * 60) {
      return const Signal(
        kind: SignalKind.collection,
        label: 'Ce matin',
        title: 'Rentre le bac avant midi',
        body: 'Le camion est passé.',
        why: 'Le règlement demande de rentrer le bac avant midi.',
        weight: .35,
        urgency: .8,
        tile: Tile(
          kind: SignalKind.collection,
          label: 'Collecte',
          value: 'Rentrer le bac',
          detail: 'avant midi',
        ),
      );
    }

    final pickup = day.next;
    if (pickup == null) return _calendarPending(now.year + 1);
    final days = day.daysToNext!;
    final when = days == 1 ? 'demain' : shortDate(pickup.day);
    return Signal(
      kind: SignalKind.collection,
      label: 'Prochaine collecte',
      title: '${_labels(pickup.streams)}, $when',
      body: 'Rien à faire pour l’instant.',
      why: 'Ta prochaine collecte est dans quelques jours.',
      weight: .65,
      urgency: days == 1
          ? .3
          : days == 2
          ? .2
          : .12,
      tile: Tile(
        kind: SignalKind.collection,
        label: 'Collecte',
        value: _labels(pickup.streams),
        detail: when,
      ),
    );
  }

  Signal _calendarPending(int year) => Signal(
    kind: SignalKind.collection,
    label: 'Collectes',
    title: 'Le calendrier $year n’est pas encore sorti',
    body: 'On l’ajoutera dès que la Ville le publie.',
    why: 'La Ville n’a pas encore mis en ligne le calendrier de l’an prochain.',
    weight: .65,
    urgency: .1,
    tile: Tile(
      kind: SignalKind.collection,
      label: 'Collecte',
      value: 'Calendrier $year',
      detail: 'bientôt',
    ),
  );

  static String _labels(List<WasteStream> s) => s.map((e) => e.label).join(' et ');
  static String _bins(List<WasteStream> s) => s.map((e) => e.bin).join(' et ');

  // Bus ------------------------------------------------------------------------

  Signal? _bus(Place place, DateTime now, {bool fixedTimes = false, TransitRealtime? live}) {
    final stop = place.stop;
    if (stop == null) return null;
    final covered = _memo(stop, 'horaire ${_day(now)}', () => stop.covers(now));
    final m = minuteOfDay(now);
    final rt = live != null && live.isFreshAt(now) ? live : null;
    // Avec le temps réel, un bus en retard de l'horaire reste dans la liste.
    final shift = <Departure, int>{};
    List<Departure>? next;
    if (covered && rt != null) {
      final candidates = stop.forDay(now).where((d) => d.minute >= m - 20);
      final predicted = [
        for (final d in candidates)
          if (d.minute + ((rt.delayFor(d) ?? 0) / 60).round() >= m) d,
      ];
      for (final d in predicted) {
        shift[d] = ((rt.delayFor(d) ?? 0) / 60).round();
      }
      predicted.sort((a, b) => (a.minute + shift[a]!).compareTo(b.minute + shift[b]!));
      next = predicted.take(3).toList();
    } else if (covered) {
      next = stop.forDay(now).where((d) => d.minute >= m).take(3).toList();
    }

    if (next == null) {
      return Signal(
        kind: SignalKind.bus,
        label: 'Bus',
        title: 'Pas d’horaire pour cette date',
        body: sentence(
          'L’horaire couvre du ${shortDate(stop.validFrom)} au ${shortDate(stop.validTo)}',
        ),
        why: 'L’horaire de la STS change à chaque saison.',
        weight: .55,
        urgency: .1,
        tile: const Tile(
          kind: SignalKind.bus,
          label: 'Bus',
          value: 'Hors période',
          detail: 'horaire',
        ),
      );
    }
    if (next.isEmpty) {
      return Signal(
        kind: SignalKind.bus,
        label: 'Bus',
        title: 'Plus de bus ce soir',
        body: 'Arrêt ${stop.name}.',
        why: 'Le dernier départ de la journée est passé.',
        weight: .55,
        urgency: .05,
        tile: Tile(
          kind: SignalKind.bus,
          label: 'Bus',
          value: 'Fini pour ce soir',
          detail: stop.name,
        ),
      );
    }

    final first = next.first;
    final late = shift[first] ?? 0;
    final at = first.minute + late;
    final wait = at - m;
    final delay = rt?.delayFor(first);
    final live2 = delay == null
        ? ''
        : late >= 1
        ? ' $late min de retard, selon la STS.'
        : late <= -1
        ? ' ${-late} min d’avance, selon la STS.'
        : ' À l’heure, selon la STS.';
    final rush = isRushHour(now);
    final then = next.length > 1
        ? ' Ensuite le ${next[1].route} à ${clockTime(next[1].minute + (shift[next[1]] ?? 0))}.'
        : '';
    return Signal(
      kind: SignalKind.bus,
      label: 'Ton bus',
      title: fixedTimes
          ? 'Le ${first.route} passe à ${clockTime(first.minute)}'
          : 'Le ${first.route} passe ${inMinutes(wait, atMinute: at)}',
      body: fixedTimes
          ? 'Vers ${first.headsign}.$then'
          : 'Vers ${first.headsign}, à ${clockTime(at)}.$live2$then',
      why: rush
          ? 'C’est l’heure où tu pars d’habitude, et ton arrêt a un départ bientôt.'
          : 'Ton arrêt a un départ bientôt.',
      weight: .55,
      urgency: rush
          ? 1
          : wait <= 20
          ? .45
          : .2,
      tile: Tile(
        kind: SignalKind.bus,
        label: 'Bus ${first.route}',
        value: clockTime(at),
        detail: wait <= 60 && !fixedTimes ? inMinutes(wait) : first.headsign,
      ),
    );
  }

  // Travaux --------------------------------------------------------------------

  Iterable<Signal> _roadworks(Place place, DateTime now) sync* {
    final rush = isRushHour(now);
    for (final nearby in place.roadworks) {
      final work = nearby.work;
      if (!work.activeAt(now)) continue;
      yield Signal(
        kind: SignalKind.roadwork,
        label: rush ? 'Sur ta route' : 'Travaux',
        title: '${work.street}, ${work.status}',
        body: work.details,
        why: nearby.onMyStreet
            ? (rush
                  ? 'Des travaux sur ta rue, à l’heure où tu pars.'
                  : 'Des travaux sur ta rue ou juste à côté.')
            : 'Des travaux ailleurs dans ton arrondissement.',
        weight: .45 * (nearby.onMyStreet ? 1 : .4),
        urgency: rush ? 1 : .5,
        tile: Tile(
          kind: SignalKind.roadwork,
          label: 'Travaux',
          value: work.shortName,
          detail: work.status,
        ),
      );
    }
  }
}

// Le widget demande des milliers de calculs d'affilée. Créer une date locale
// coûte cher (un fuseau à consulter) : ce qui ne dépend que du jour se calcule
// une fois par jour et par objet.

final _memos = Expando<Map<String, Object?>>('memos');

T _memo<T>(Object owner, String key, T Function() compute) {
  final map = _memos[owner] ??= <String, Object?>{};
  if (map.length > 400) map.clear();
  if (map.containsKey(key)) return map[key] as T;
  final value = compute();
  map[key] = value;
  return value;
}

String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

class _CollectionDay {
  _CollectionDay(CollectionSchedule s, DateTime now) {
    final tomorrowDate = addDays(now, 1);
    coversToday = s.covers(now);
    coversTomorrow = s.covers(tomorrowDate);
    today = s.on(now);
    tomorrow = s.on(tomorrowDate);
    next = s.next(tomorrowDate);
    final n = next;
    daysToNext = n == null ? null : dayNumber(n.day) - dayNumber(now);
  }

  late final bool coversToday;
  late final bool coversTomorrow;
  late final List<WasteStream> today;
  late final List<WasteStream> tomorrow;
  late final Pickup? next;
  late final int? daysToNext;
}

class _ParkingDay {
  _ParkingDay(WinterParking p, DateTime now)
    : appliesToday = p.appliesOn(now),
      appliesTonight = p.appliesTonight(now),
      daysToSeason = dayNumber(p.nextSeasonStart(now)) - dayNumber(now);

  final bool appliesToday;
  final bool appliesTonight;
  final int daysToSeason;
}
