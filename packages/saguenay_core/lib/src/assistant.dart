import 'agenda.dart';
import 'calendar.dart';
import 'collection.dart';
import 'format.dart';
import 'geo.dart';
import 'parking.dart';
import 'place.dart';
import 'relevance.dart';
import 'signal.dart';
import 'sorting.dart';
import 'water.dart';

class AssistantAnswer {
  const AssistantAnswer(this.text, {this.kind, this.sources = const [], this.understood = true});

  final String text;

  /// La fiche à proposer en dessous de la réponse.
  final SignalKind? kind;
  final List<String> sources;

  /// Faux quand l'assistant n'a pas compris : l'app peut alors proposer
  /// l'assistant en ligne, s'il est activé.
  final bool understood;
}

/// Répond aux questions courantes à partir des données de l'app, sur le
/// téléphone, sans réseau et sans rien envoyer. Chaque réponse dit d'où elle
/// vient. Pour le reste, l'app peut passer la main à l'assistant en ligne.
class LocalAssistant {
  const LocalAssistant({
    this.engine = const RelevanceEngine(),
    this.parking = const WinterParking(),
  });

  final RelevanceEngine engine;
  final WinterParking parking;

  static const suggestions = [
    'Le bac, c’est quand ?',
    'Je peux me stationner dans la rue cette nuit ?',
    'L’eau est-elle bonne à boire ?',
    'Prochain bus ?',
    'Ça va où, une boîte de pizza ?',
    'Va-t-il neiger cette nuit ?',
  ];

  AssistantAnswer answer(String question, Place place, CityData city, DateTime now) {
    final a = _answer(question, place, city, now);
    // « mardi 27 oct. » en fin de phrase ne prend pas un second point.
    final text = a.text.replaceAll(RegExp(r'(?<!\.)\.\.(?!\.)'), '.');
    return text == a.text
        ? a
        : AssistantAnswer(text, kind: a.kind, sources: a.sources, understood: a.understood);
  }

  AssistantAnswer _answer(String question, Place place, CityData city, DateTime now) {
    final q = ' ${streetKey(question)} ';
    bool has(List<String> words) => words.any((w) => q.contains(' $w'));

    // « Ça va où ? » parle de tri ; « je sors quel bac cette semaine ? » parle
    // de calendrier, même s'il nomme un bac.
    final sorting = SortingGuide.lookup(question);
    final when = has([
      'quand',
      'sors',
      'sort ',
      'sortir',
      'semaine',
      'demain',
      'ce soir',
      'aujourd',
      'prochain',
      'passe',
    ]);
    final asksWhere =
        has(['ca va ou', 'jeter', 'composter', 'trier']) || (has(['quel bac', 'recycl']) && !when);
    if (asksWhere || (sorting != null && !when)) return _sorting(sorting);
    // Le premier thème reconnu l'emporte : le stationnement avant les collectes,
    // pour que « la déneigeuse » ne parte pas sur le bac.
    final topics = <(List<String>, AssistantAnswer Function())>[
      (
        [
          'stationn',
          'garer',
          'auto dans la rue',
          'char dans la rue',
          'voiture dans la rue',
          'deneig',
        ],
        () => _parking(now),
      ),
      (
        [
          'bac',
          'collecte',
          'poubelle',
          'vidange',
          'ordure',
          'dechet',
          'compost',
          'recycl',
          'recuperation',
        ],
        () => _collection(place, now),
      ),
      (['eau', 'bouillir', 'potable', 'aqueduc', 'ebullition'], () => _water(place, city, now)),
      (['bus', 'autobus', 'sts', 'transport'], () => _bus(place, city, now)),
      (
        ['meteo', 'neig', 'pluie', 'temperature', 'froid', 'tempete', 'verglas'],
        () => _weather(city, now),
      ),
      (['courant', 'electricite', 'panne', 'hydro'], () => _power(place, city, now)),
      (['route', 'chaussee', 'parc des laurentides', '175', '170', '172'], () => _roads(city, now)),
      (['travaux', 'chantier', 'detour', 'rue fermee'], () => _roadworks(place, now)),
      (['urgence', 'hopital', 'attente', 'civiere'], () => _emergency(city)),
      (['semaine', 'demain', 'prevu', 'a venir'], () => _week(place, city, now)),
      (['aujourd hui', 'quoi de neuf', 'important', 'resume'], () => _today(place, city, now)),
    ];
    for (final (words, reply) in topics) {
      if (has(words)) return reply();
    }
    return const AssistantAnswer(
      'Je ne sais pas encore répondre à ça. Je connais les collectes, le stationnement, l’eau, '
      'le bus, la météo, les pannes, les routes, les travaux, les urgences et le tri.',
      understood: false,
    );
  }

  AssistantAnswer _sorting(SortingAnswer? s) {
    if (s == null) {
      return const AssistantAnswer(
        'Dis-moi l’objet, par exemple « Ça va où, un carton de lait ? ». En cas de doute, '
        'l’application Ça va où? de RECYC-QUÉBEC connaît presque tout.',
        sources: [SortingGuide.source],
      );
    }
    final where = switch (s.place) {
      SortingPlace.notBrown || SortingPlace.notBlue =>
        '${capitalize(s.item)} : ${s.place.label}. ${s.note} Pour le bon endroit, vérifie dans Ça va où? de RECYC-QUÉBEC.',
      _ => '${capitalize(s.item)} : ${s.place.label}. ${s.note}',
    };
    return AssistantAnswer(
      where,
      kind: SignalKind.collection,
      sources: const [SortingGuide.source],
    );
  }

  AssistantAnswer _parking(DateTime now) {
    const source = ['Règlement VS-R-2006-44 de la Ville'];
    if (parking.inForceAt(now)) {
      return const AssistantAnswer(
        'Non. C’est interdit en ce moment, jusqu’à 7 h, dans toutes les rues. L’amende est de 45 \$.',
        kind: SignalKind.parking,
        sources: source,
      );
    }
    if (parking.appliesTonight(now)) {
      return const AssistantAnswer(
        'Non. Cette nuit, c’est interdit de minuit à 7 h, partout en ville. L’amende est de 45 \$.',
        kind: SignalKind.parking,
        sources: source,
      );
    }
    final start = parking.nextSeasonStart(now);
    return AssistantAnswer(
      'Oui, cette nuit c’est permis. L’interdiction de nuit reprend le ${longDate(start)}, de minuit à 7 h.',
      kind: SignalKind.parking,
      sources: source,
    );
  }

  AssistantAnswer _collection(Place place, DateTime now) {
    if (place.collectionMissing) {
      return const AssistantAnswer(
        'Je n’ai pas encore l’horaire de ton adresse. Il arrivera dès que le téléphone aura du réseau.',
        kind: SignalKind.collection,
      );
    }
    final next = place.collection.upcoming(now, count: 3);
    if (next.isEmpty) {
      return const AssistantAnswer(
        'Le calendrier de l’an prochain n’est pas encore publié par la Ville.',
        kind: SignalKind.collection,
      );
    }
    String when(DateTime d) => sameDay(d, now)
        ? 'aujourd’hui'
        : sameDay(d, addDays(now, 1))
        ? 'demain'
        : shortDate(d);
    final first = next.first;
    final rest = next
        .skip(1)
        .map((p) => '${_names(p.streams).toLowerCase()} ${when(p.day)}')
        .join(', ');
    final tip = sameDay(first.day, addDays(now, 1))
        ? ' Sors ${first.streams.map((s) => s.bin).join(' et ')} ce soir.'
        : '';
    return AssistantAnswer(
      '${_names(first.streams)} ${when(first.day)}.$tip${rest.isEmpty ? '' : ' Ensuite : $rest.'}',
      kind: SignalKind.collection,
      sources: const ['Horaire des collectes de la Ville'],
    );
  }

  static String _names(List<WasteStream> s) => s.map((e) => e.label).join(' et ');

  AssistantAnswer _water(Place place, CityData city, DateTime now) {
    const source = ['Carte des avis d’aqueduc de la Ville'];
    for (final number in place.waterNotices) {
      final n = city.waterNotices.where((w) => w.number == number).firstOrNull;
      if (n == null) continue;
      final state = n.stateAt(now, knownUntil: city.waterKnownUntil);
      if (state == NoticeState.active && n.type == WaterNoticeType.boil) {
        return const AssistantAnswer(
          'Non, pas sans la faire bouillir. Un avis d’ébullition touche ton adresse : au moins une minute à gros bouillons.',
          kind: SignalKind.water,
          sources: source,
        );
      }
      if (state == NoticeState.active) {
        return AssistantAnswer(
          '${n.type.label} en cours à ton adresse.',
          kind: SignalKind.water,
          sources: source,
        );
      }
      if (state == NoticeState.upcoming) {
        return AssistantAnswer(
          'Oui pour l’instant. Mais ${n.type.label.toLowerCase()} prévu ${shortDate(n.start)} à ${clockTimeOf(n.start)}.',
          kind: SignalKind.water,
          sources: source,
        );
      }
    }
    return const AssistantAnswer(
      'Oui. Aucun avis d’aqueduc ne touche ton adresse en ce moment.',
      kind: SignalKind.water,
      sources: source,
    );
  }

  AssistantAnswer _bus(Place place, CityData city, DateTime now) {
    final s = engine.signals(place, city, now).where((s) => s.kind == SignalKind.bus).firstOrNull;
    if (s == null) {
      return const AssistantAnswer(
        'Aucun arrêt de bus n’est associé à ton adresse.',
        kind: SignalKind.bus,
      );
    }
    return AssistantAnswer(
      '${s.title}. ${s.body}',
      kind: SignalKind.bus,
      sources: const ['Société de transport du Saguenay'],
    );
  }

  AssistantAnswer _weather(CityData city, DateTime now) {
    final w = city.weather;
    const source = ['Environnement Canada'];
    if (w == null) {
      return const AssistantAnswer(
        'La météo arrive dès que le téléphone a du réseau.',
        kind: SignalKind.weather,
      );
    }
    final alert = w.alerts.where((a) => a.activeAt(now)).firstOrNull;
    final temp = w.temperature == null
        ? ''
        : ' Il fait ${temperatureLabel(w.temperature!)}${w.condition == null ? '' : ', ${w.condition!.toLowerCase()}'}.';
    final snow = w.snowTonightCm;
    final snowText = snow == null || snow == 0
        ? ' Pas de neige annoncée cette nuit.'
        : ' Jusqu’à $snow cm de neige cette nuit.';
    final alertText = alert == null
        ? ''
        : ' ${alert.name} en vigueur${alert.what == null ? '' : ' : ${alert.what}'}';
    return AssistantAnswer(
      '$alertText$temp$snowText'.trim(),
      kind: SignalKind.weather,
      sources: source,
    );
  }

  AssistantAnswer _power(Place place, CityData city, DateTime now) {
    final s = engine.signals(place, city, now).where((s) => s.kind == SignalKind.power).firstOrNull;
    if (city.power == null) {
      return const AssistantAnswer(
        'Les pannes arrivent dès que le téléphone a du réseau.',
        kind: SignalKind.power,
      );
    }
    return AssistantAnswer(
      s == null ? 'Aucune panne ni coupure planifiée dans ton secteur.' : '${s.title}. ${s.body}',
      kind: SignalKind.power,
      sources: const ['Hydro-Québec'],
    );
  }

  AssistantAnswer _roads(CityData city, DateTime now) {
    final r = city.roads;
    if (r == null) {
      return const AssistantAnswer(
        'L’état des routes arrive dès que le téléphone a du réseau.',
        kind: SignalKind.roads,
      );
    }
    final p175 = r.segments.where((s) => s.route == 175).toList();
    final worst = r.worst;
    final parc = p175.isEmpty
        ? ''
        : ' Route 175 : ${p175.first.surface.toLowerCase()}, visibilité ${p175.first.visibility.toLowerCase()}.';
    return AssistantAnswer(
      worst == null
          ? 'Les routes autour de Saguenay sont dégagées.$parc'
          : 'Route ${worst.route} : ${worst.surface.toLowerCase()} entre ${worst.from} et ${worst.to}.$parc',
      kind: SignalKind.roads,
      sources: const ['Ministère des Transports, Québec 511'],
    );
  }

  AssistantAnswer _roadworks(Place place, DateTime now) {
    final works = place.roadworks.where((w) => !w.work.isOverAt(now)).toList();
    if (works.isEmpty) {
      return const AssistantAnswer('Aucuns travaux près de chez toi.', kind: SignalKind.roadwork);
    }
    final mine = works.where((w) => w.onMyStreet).map((w) => w.work).firstOrNull;
    final first = mine ?? works.first.work;
    return AssistantAnswer(
      '${mine == null ? 'Près de chez toi' : 'Sur ta rue'} : ${first.street}, ${first.status}, jusqu’au ${first.end.day} ${shortDate(first.end).split(' ').last}.',
      kind: SignalKind.roadwork,
      sources: const ['Ville de Saguenay, état de la circulation'],
    );
  }

  AssistantAnswer _emergency(CityData city) {
    final rooms = city.emergencies?.rooms ?? const [];
    final lines = rooms
        .map((r) => '${r.hospital} ${r.occupancyPercent == null ? '' : '${r.occupancyPercent} %'}')
        .join(', ');
    return AssistantAnswer(
      'Occupation des civières : $lines. Ces chiffres ne disent rien du triage : ne choisis pas un hôpital '
      'd’après eux. Urgence : 911. Conseil santé : 811.',
      kind: SignalKind.emergency,
      sources: const ['Ministère de la Santé'],
    );
  }

  AssistantAnswer _week(Place place, CityData city, DateTime now) {
    final summary = const Agenda().week(place, city, now).summary(max: 4);
    return AssistantAnswer(
      summary ?? 'Rien de prévu cette semaine.',
      sources: const ['Calculé sur le téléphone'],
    );
  }

  AssistantAnswer _today(Place place, CityData city, DateTime now) {
    final t = engine.today(place, city, now);
    final hero = t.hero;
    return AssistantAnswer(
      hero == null ? 'Rien de spécial pour l’instant.' : '${hero.title}. ${hero.body}',
      kind: hero?.kind,
    );
  }
}
