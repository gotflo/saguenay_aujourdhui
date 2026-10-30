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
/// Un thème que l'app connaît, et la forme des questions auxquelles elle sait
/// répondre seule. Le reste part à l'assistant en ligne : mieux vaut lui passer
/// une question de trop que répondre « Oui » à côté.
class _Topic {
  const _Topic(
    this.words,
    this.reply, {
    this.shape = const [],
    this.nowOnly = false,
    this.isBus = false,
    this.isRoad = false,
    this.broad = false,
  });

  final List<String> words;
  final AssistantAnswer Function() reply;
  final List<String> shape;

  /// La réponse dit l'état de maintenant, à l'adresse.
  final bool nowOnly;
  final bool isBus;
  final bool isRoad;

  /// « Quoi de neuf ? » : ne compte pas comme un second sujet.
  final bool broad;
}

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

  /// La vie de quelqu'un peut être en jeu : on répond tout de suite, sans réseau.
  static const _danger = [
    'ne respire',
    'respire plus',
    'respire pas',
    'inconscient',
    'mal a la poitrine',
    'douleur a la poitrine',
    'crise cardiaque',
    'avc ',
    'etouffe',
    'surdose',
    'overdose',
    'saigne',
    'hemorragie',
    'feu chez',
    'au feu ',
    'le feu dans',
    'ca brule',
    'incendie',
    'odeur de gaz',
    'fuite de gaz',
    'monoxyde',
  ];
  static const _crisis = [
    'suicid',
    'me tuer',
    'me faire du mal',
    'en finir',
    'plus envie de vivre',
    'envie de mourir',
    'veux mourir',
  ];
  static const _greetings = {'bonjour', 'salut', 'allo', 'bonsoir', 'merci', 'coucou', 'hello'};

  /// Une explication, un prix, un numéro : les données de l'adresse n'y répondent pas.
  static const _explains = [
    'pourquoi',
    'combien',
    'c est quoi',
    'cest quoi',
    'qu est ce',
    'quest ce',
    'explique',
    'que faire',
    'quoi faire',
    'je fais quoi',
    'on fait quoi',
    'je dois faire',
    'veut dire',
    'qui ',
    'numero',
    'telephone',
    'tarif',
    'prix',
    'coute',
    'cout ',
    'amende',
    'finit',
    'finis',
    'jusqu',
    'facture',
    'depuis',
  ];

  /// Un problème à raconter plutôt qu'un état à lire.
  static const _complaints = [
    'pas ete',
    'pas passe',
    'n a pas',
    'n ont pas',
    'n est pas',
    'oublie',
    'en retard',
  ];

  /// Un autre moment que maintenant.
  static const _otherTimes = [
    'demain',
    'hier',
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
    'fin de semaine',
    'semaine',
    'mois ',
    'hiver',
    'printemps',
    'automne',
    'ete ',
    'janvier',
    'fevrier',
    'mars ',
    'avril',
    'mai ',
    'juin',
    'juillet',
    'aout',
    'septembre',
    'octobre',
    'novembre',
    'decembre',
  ];

  /// Un autre endroit que l'adresse.
  static const _otherPlaces = [
    'a jonquiere',
    'a chicoutimi',
    'a la baie',
    'de jonquiere',
    'de chicoutimi',
    'de la baie',
    'a laterriere',
    'a shipshaw',
    'au lac kenogami',
    'a lac kenogami',
    'a canton tremblay',
    'sur la rue',
    'sur le boulevard',
    'a l adresse',
  ];

  static const _busTrips = [
    'pour aller',
    'pour me rendre',
    'pour la ',
    'pour le ',
    'vers ',
    'de la ligne',
  ];

  static const _unknown = AssistantAnswer(
    'Je ne sais pas encore répondre à ça. Je connais les collectes, le stationnement, l’eau, '
    'le bus, la météo, les pannes, les routes, les travaux, les urgences et le tri.',
    understood: false,
  );

  /// Le mieux que l'app puisse dire si l'assistant en ligne ne répond pas.
  static AssistantAnswer _forOnline(AssistantAnswer best) =>
      AssistantAnswer(_unknown.text, kind: best.kind, understood: false);

  AssistantAnswer _answer(String question, Place place, CityData city, DateTime now) {
    final q =
        ' ${streetKey(question).replaceAll(RegExp(r'[?!:;«»()"]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
    bool has(List<String> words) => words.any((w) => q.contains(' $w'));
    final words = q.trim().split(' ');

    if (has(_crisis)) {
      return const AssistantAnswer(
        'Parle à quelqu’un maintenant : 1 866 APPELLE (1 866 277-3553), jour et nuit, ou par '
        'texto au 535353. Si le danger est immédiat, appelle le 911.',
      );
    }
    if (has(_danger)) {
      return const AssistantAnswer(
        'Appelle le 911 maintenant. S’il y a un feu ou une odeur de gaz, sors d’abord du bâtiment.',
      );
    }
    if (words.length <= 3 && _greetings.contains(words.first)) {
      return const AssistantAnswer(
        'Avec plaisir ! Demande-moi le bac, le stationnement, l’eau, le bus, la météo ou où jeter un objet.',
      );
    }
    // « Et demain ? » dépend de la question d'avant : seul l'assistant en ligne l'a.
    if (words.first == 'et') return _unknown;

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
        has(['ca va ou', 'jeter', 'composter', 'trier', 'debarrasser']) ||
        (has(['quel bac', 'recycl']) && !when);
    // « L'eau goûte le chlore » nomme une matière, mais ne demande pas où la jeter.
    final aboutSorting =
        asksWhere ||
        has(['va ou', 'ou va', 'ou mettre', 'mettre', 'va dans', 'bac ', 'poubelle']) ||
        words.length <= 3;
    if (sorting != null && !when && aboutSorting) {
      return has(['pourquoi']) ? _forOnline(_sorting(sorting)) : _sorting(sorting);
    }
    if (asksWhere) {
      final object = words.where((w) => !_sortingWords.contains(w)).isNotEmpty;
      return object
          ? const AssistantAnswer(
              'Je n’ai pas cet objet dans les règles de la Ville. L’application Ça va où? de '
              'RECYC-QUÉBEC connaît presque tout.',
              kind: SignalKind.collection,
              understood: false,
            )
          : _sorting(null);
    }

    final topics = <_Topic>[
      _Topic(
        [
          'stationn',
          'garer',
          'me gare',
          'auto dans la rue',
          'char dans la rue',
          'voiture dans la rue',
        ],
        () => _parking(now),
        shape: [
          'je peux',
          'on peut',
          'peut on',
          'puis je',
          'permis',
          'interdit',
          'droit de',
          'laisser',
          'cette nuit',
          'ce soir',
        ],
        nowOnly: true,
      ),
      _Topic(
        [
          'bac ',
          'bacs ',
          'collecte',
          'poubelle',
          'vidange',
          'ordure',
          'dechet',
          'compost',
          'recycl',
          'recuperation',
        ],
        () => _collection(place, now, asked: _streamIn(has)),
        shape: [
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
          'quel jour',
          'quel bac',
        ],
      ),
      _Topic(
        ['eau ', 'eaux ', 'leau ', 'bouillir', 'potable', 'aqueduc', 'ebullition'],
        () => _water(place, city, now),
        shape: [
          'bonne',
          'boire',
          'buvable',
          'potable',
          'bouillir',
          'ebullition',
          'aqueduc',
          'avis',
          'coupee',
          'coupure',
        ],
        nowOnly: true,
      ),
      _Topic(
        ['bus ', 'autobus ', 'sts '],
        () => _bus(place, city, now),
        shape: ['prochain', 'passe', 'quand', 'quelle heure', 'horaire'],
        nowOnly: true,
        isBus: true,
      ),
      _Topic(
        ['meteo', 'neig', 'pluie', 'pleuv', 'temperature', 'froid', 'tempete', 'verglas'],
        () => _weather(city, now),
        nowOnly: true,
      ),
      _Topic(
        [
          'panne',
          'coupure',
          'plus de courant',
          'pas de courant',
          'plus d electricite',
          'pas d electricite',
        ],
        () => _power(place, city, now),
        nowOnly: true,
      ),
      _Topic(
        ['route ', 'routes ', 'chaussee', 'parc des laurentides', '175 '],
        () => _roads(city, now),
        nowOnly: true,
        isRoad: true,
      ),
      _Topic(['travaux', 'chantier', 'detour', 'rue fermee'], () => _roadworks(place, now)),
      _Topic(
        ['urgence', 'hopital', 'civiere'],
        () => _emergency(city),
        shape: ['plein', 'occupation', 'civiere', 'achalandage'],
      ),
      _Topic(
        ['semaine', 'demain', 'prevu', 'a venir'],
        () => _week(place, city, now),
        shape: ['prevu', 'a venir', 'quoi', 'ma semaine', 'cette semaine'],
        broad: true,
      ),
      _Topic(
        ['aujourd hui', 'quoi de neuf', 'resume'],
        () => _today(place, city, now),
        broad: true,
      ),
    ];
    final found = topics.where((t) => has(t.words)).toList();
    if (found.isEmpty) return _unknown;
    final topic = found.first;

    final explains =
        has(_explains) ||
        q.startsWith(' ou ') ||
        (has(['comment ']) && !has(['comment est', 'comment sont', 'comment va']));
    final otherRoad = RegExp(r' (?:route|autoroute) (\d+) ').firstMatch(q)?.group(1);
    if (explains ||
        has(_complaints) ||
        words.length > 14 ||
        (topic.shape.isNotEmpty && words.length > 3 && !has(topic.shape)) ||
        (topic.nowOnly && (has(_otherTimes) || has(_otherPlaces))) ||
        (topic.isBus &&
            (has(_busTrips) || RegExp(r' (?:bus|autobus|ligne|circuit) \d+ ').hasMatch(q))) ||
        (topic.isRoad && otherRoad != null && otherRoad != '175')) {
      return _forOnline(topic.reply());
    }
    // Deux sujets dans la même phrase : en ligne si possible, sinon les deux réponses.
    final distinct = found.where((t) => !t.broad).toList();
    if (distinct.length > 1) {
      final both = distinct.take(2).map((t) => t.reply()).toList();
      return AssistantAnswer(
        both.map((a) => a.text).join(' '),
        kind: both.first.kind,
        sources: [for (final a in both) ...a.sources],
        understood: false,
      );
    }
    return topic.reply();
  }

  static const _sortingWords = {
    'ca',
    'va',
    'ou',
    'quel',
    'quelle',
    'bac',
    'jeter',
    'je',
    'j',
    'on',
    'peut',
    'peux',
    'trier',
    'recycler',
    'recycle',
    'composter',
    'se',
    'un',
    'une',
    'le',
    'la',
    'les',
    'des',
    'du',
    'de',
    'mon',
    'ma',
    'mes',
    'ce',
    'cet',
    'cette',
    'est',
    'il',
    'faut',
    'mettre',
    'debarrasser',
    'me',
    'comment',
  };

  static WasteStream? _streamIn(bool Function(List<String>) has) {
    if (has(['compost', 'bac brun', 'brun ', 'matiere organique', 'matieres organiques'])) {
      return WasteStream.compost;
    }
    if (has(['recycl', 'bac bleu', 'bleu ', 'recuperation'])) return WasteStream.recycling;
    if (has(['ordure', 'poubelle', 'vidange', 'dechet'])) return WasteStream.garbage;
    return null;
  }

  /// Ce que l'app transmet à l'assistant en ligne : le secteur et ce qu'elle
  /// sait pour lui, jamais l'adresse ni ce qui dirait qu'une rue est la sienne.
  Map<String, Object?> briefing(Place place, CityData city, DateTime now) {
    String safe(String s) => s
        .replaceAll('Sur ta rue', 'Tout près')
        .replaceAll('sur ta rue', 'tout près')
        .replaceAll('à ton adresse', 'dans ton secteur');
    final today = engine.today(place, city, now);
    final lat = place.lat, lon = place.lon;
    final hasSpot = lat != null && lon != null;
    final air = hasSpot ? city.air?.nearest(lat, lon, now) : null;
    final ban = hasSpot ? city.fireBans?.at(lat, lon) : null;
    final peak = city.peaks?.next(now);
    return {
      'secteur': place.sector ?? 'Saguenay',
      'moment': '${longDate(now)}, ${clockTimeOf(now)}',
      'carte': today.hero == null ? null : safe('${today.hero!.title}. ${today.hero!.body}'),
      'tuiles': [for (final t in today.tiles) safe('${t.label} : ${t.value} (${t.detail})')],
      'semaine': switch (const Agenda().week(place, city, now).summary(max: 6)) {
        final String week => safe(week),
        null => null,
      },
      'eau': safe(_water(place, city, now).text),
      'stationnement': _parking(now).text,
      'collectes': _collection(place, now).text,
      'bus': _bus(place, city, now).text,
      'meteo': _weather(city, now).text,
      'previsions': city.weather?.forecast ?? const <String>[],
      'pannes': safe(_power(place, city, now).text),
      'routes': _roads(city, now).text,
      'travaux': safe(_roadworks(place, now).text),
      'urgences': _emergency(city).text,
      if (air != null)
        'air': 'Indice ${air.index} (${air.level.label}) à la station ${air.shortName}.',
      if (hasSpot && city.fireBans != null)
        'feux': ban == null
            ? 'Aucune interdiction de feux à ciel ouvert dans ton secteur.'
            : 'Feux à ciel ouvert interdits : ${ban.description}',
      if (city.peaks != null)
        'pointes': peak == null
            ? 'Aucune pointe d’Hydro-Québec annoncée dans les 36 prochaines heures.'
            : 'Pointe d’Hydro-Québec le ${longDate(peak.start)}, de ${clockTimeOf(peak.start)} à '
                  '${clockTimeOf(peak.end)} (${peak.offersLabel}).',
    };
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

  AssistantAnswer _collection(Place place, DateTime now, {WasteStream? asked}) {
    if (place.collectionMissing) {
      return const AssistantAnswer(
        'Je n’ai pas encore l’horaire de ton adresse. Il arrivera dès que le téléphone aura du réseau.',
        kind: SignalKind.collection,
      );
    }
    final next = place.collection.upcoming(now, count: asked == null ? 3 : 6);
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
    final first =
        next.where((p) => asked == null || p.streams.contains(asked)).firstOrNull ?? next.first;
    final rest = next
        .where((p) => !identical(p, first))
        .take(2)
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
    if (rooms.isEmpty) {
      return const AssistantAnswer(
        'Je n’ai pas les chiffres des urgences pour l’instant. Urgence : 911. Conseil santé : 811.',
        kind: SignalKind.emergency,
      );
    }
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
