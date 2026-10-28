import 'dart:convert';
import 'dart:io';

import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, Object?>;

void main() {
  const engine = RelevanceEngine();
  final racine = Demo.place('racine');
  final evening = DateTime(2026, 10, 27, 23, 30);
  const maman = ResolvedAddress(
    civic: '2687',
    street: 'Boulevard du Royaume',
    sector: 'Jonquière',
    lat: 48.4051,
    lon: -71.1738,
    name: 'Chez maman',
  );

  group('qualité de l’air (vraie réponse du 27 octobre 2026, 23 h)', () {
    final readings = parseAirQuality(fixture('qualite_air.json'));

    test('les deux stations de Saguenay, en heure locale', () {
      expect(readings.map((r) => r.shortName), unorderedEquals(['Parc Powell', 'UQAC']));
      final uqac = readings.firstWhere((r) => r.station == '02022');
      expect(uqac.index, 13);
      expect(uqac.level, AirLevel.good);
      expect(uqac.at, DateTime(2026, 10, 27, 23));
    });

    test('la station la plus proche, et rien quand l’air est bon', () {
      final air = AirSnapshot(takenAt: evening, readings: readings);
      expect(air.nearest(48.428, -71.062, evening)!.shortName, 'UQAC');
      expect(air.nearest(48.42, -71.24, evening)!.shortName, 'Parc Powell');
      final today = engine.today(racine, CityData(air: air), evening);
      expect(today.signals.where((s) => s.title.contains('air')), isEmpty);
      expect(today.tiles.where((t) => t.label == 'Air'), isEmpty);
    });

    test('l’air mauvais monte, et une seule alerte par jour', () {
      final poor = AirSnapshot(
        takenAt: evening,
        readings: [
          AirReading(
            station: '02022',
            name: 'Saguenay - UQAC',
            lat: 48.416,
            lon: -71.052,
            index: 62,
            at: DateTime(2026, 7, 2, 14),
          ),
        ],
      );
      final at = DateTime(2026, 7, 2, 14, 30);
      final s = engine.signals(racine, CityData(air: poor), at).first;
      expect(s.title, 'L’air est de mauvaise qualité');
      expect(s.why, contains('62'));
      final alerts = AirAlerts.due(racine, CityData(air: poor), at);
      expect(alerts.single.key, 'air:02022:2026-07-02');
      expect(
        AirAlerts.due(racine, CityData(air: poor), at, alreadySent: {alerts.single.key}),
        isEmpty,
      );
    });

    test('une mesure de plus de trois heures ne compte plus', () {
      final air = AirSnapshot(takenAt: evening, readings: readings);
      expect(air.nearest(48.428, -71.062, evening.add(const Duration(hours: 4))), isNull);
    });
  });

  group('interdictions de feux', () {
    test('la vraie réponse : aucune interdiction en vigueur', () {
      final bans = parseFireBans(fixture('interdiction_feux.json'));
      expect(bans.single.active, isFalse);
      expect(bans.single.since, DateTime(2026, 7, 20));
      expect(FireBanSnapshot(takenAt: evening, bans: bans).at(48.35, -71.33), isNull);
    });

    test('une interdiction qui couvre un chalet du lac Kénogami', () {
      final ban = FireBan(
        measure:
            'INTERDICTION - Interdiction de faire des feux à ciel ouvert en forêt ou à proximité',
        since: DateTime(2026, 7, 2),
        rings: const [
          [(-71.6, 48.2), (-71.0, 48.2), (-71.0, 48.5), (-71.6, 48.5), (-71.6, 48.2)],
        ],
      );
      final snapshot = FireBanSnapshot(takenAt: evening, bans: [ban]);
      expect(snapshot.at(48.35, -71.33), same(ban));
      expect(snapshot.at(48.6, -70.8), isNull);
      final chalet = livePlace(
        const ResolvedAddress(
          civic: '1500',
          street: 'Chemin du Lac-Kénogami',
          sector: 'Lac Kénogami',
          lat: 48.35,
          lon: -71.33,
        ),
      );
      final s = engine
          .signals(chalet, CityData(fireBans: snapshot), DateTime(2026, 7, 3, 18))
          .firstWhere((s) => s.label == 'Feux');
      expect(s.body, 'Interdiction de faire des feux à ciel ouvert en forêt ou à proximité');
      expect(s.why, contains('2 juillet'));
    });

    test('le JSON garde la zone', () {
      final ban = parseFireBans(fixture('interdiction_feux.json')).single;
      final back = FireBan.fromJson(jsonDecode(jsonEncode(ban.toJson())) as Map<String, Object?>);
      expect(back.rings.single.length, ban.rings.single.length);
      expect(back.since, ban.since);
    });
  });

  group('pointes d’Hydro-Québec (vraie réponse)', () {
    final events = parsePeakEvents(fixture('pointes_hydro.json'));

    test('les offres aux mêmes heures ne font qu’une pointe, en heure locale', () {
      final march18 = events.firstWhere((e) => sameDay(e.start, DateTime(2026, 3, 18)));
      expect(march18.start, DateTime(2026, 3, 18, 6));
      expect(march18.end, DateTime(2026, 3, 18, 10));
      expect(march18.offersLabel, 'Crédit hivernal et Flex D');
      expect(events.map((e) => e.key).toSet(), hasLength(events.length));
    });

    test('la veille au soir : une tuile et une seule alerte', () {
      final peaks = PeakSnapshot(takenAt: evening, events: events);
      final eve = DateTime(2026, 3, 17, 19);
      final s = engine
          .signals(racine, CityData(peaks: peaks), eve)
          .firstWhere((s) => s.tile.label == 'Pointe');
      expect(s.label, 'Demain');
      expect(s.title, 'Pointe d’Hydro-Québec de 6 h à 10 h');
      final alert = PeakAlerts.due(CityData(peaks: peaks), eve).single;
      expect(alert.title, 'Pointe d’Hydro-Québec demain, de 6 h à 10 h');
      expect(alert.kind, ReminderKind.peak);
      expect(PeakAlerts.due(CityData(peaks: peaks), eve, alreadySent: {alert.key}), isEmpty);
    });

    test('pendant la pointe, puis plus rien', () {
      final peaks = PeakSnapshot(takenAt: evening, events: events);
      final during = engine
          .signals(racine, CityData(peaks: peaks), DateTime(2026, 3, 18, 8))
          .firstWhere((s) => s.tile.label == 'Pointe');
      expect(during.title, 'Pointe d’Hydro-Québec jusqu’à 10 h');
      expect(
        engine
            .signals(racine, CityData(peaks: peaks), DateTime(2026, 3, 18, 11))
            .where((s) => s.tile.label == 'Pointe'),
        isEmpty,
      );
    });
  });

  group('adresses suivies', () {

    test('le nom voyage avec l’adresse, sans changer son identifiant', () {
      final back = ResolvedAddress.fromJson(
        jsonDecode(jsonEncode(maman.toJson())) as Map<String, Object?>,
      );
      expect(back.name, 'Chez maman');
      expect(back.displayName, 'Chez maman');
      expect(back.id, maman.named(null).id);
      expect(maman.named('  ').name, isNull);
    });

    test('le lien de partage : aller-retour, et refus de ce qui est hors de Saguenay', () {
      final link = AddressLink.encode(maman);
      expect(link.scheme, 'aujourdhui');
      final back = AddressLink.decode(Uri.parse(link.toString()))!;
      expect(back.id, maman.id);
      expect(back.name, 'Chez maman');
      expect(
        AddressLink.decode(link.replace(queryParameters: {...link.queryParameters, 'la': '45.5'})),
        isNull,
      );
      expect(
        AddressLink.decode(
          link.replace(queryParameters: {...link.queryParameters, 's': 'Montréal'}),
        ),
        isNull,
      );
      expect(
        AddressLink.decode(
          link.replace(queryParameters: {...link.queryParameters, 'c': '<script>'}),
        ),
        isNull,
      );
      expect(AddressLink.decode(Uri.parse('https://exemple.ca/adresse')), isNull);
    });

    test('un avis d’ébullition chez un proche : nommé, et distinct du sien', () {
      final boil = WaterNotice(
        number: '2026-401',
        type: WaterNoticeType.boil,
        start: DateTime(2026, 10, 27, 8),
        zone: 'Jonquière, secteur Royaume',
        rings: const [
          [(-71.18, 48.40), (-71.16, 48.40), (-71.16, 48.41), (-71.18, 48.41), (-71.18, 48.40)],
        ],
      );
      final water = WaterSnapshot(takenAt: evening, notices: [boil]);
      final place = livePlace(maman, water: water);
      final city = CityData(waterNotices: water.notices, waterKnownUntil: water.knownUntil);
      final mine = WaterAlerts.due(place, city, evening).single;
      final theirs = WaterAlerts.due(place, city, evening, who: 'Chez maman').single;
      expect(theirs.title, 'Chez maman : avis d’ébullition');
      expect(mine.title, 'Avis d’ébullition à ton adresse');
      expect(theirs.key, isNot(mine.key));
      expect(theirs.id, isNot(mine.id));
      expect(QuietHours.deferral(theirs, DateTime(2026, 10, 27, 23)), isNull);
    });

    test('une panne chez un proche, signalée une fois', () {
      final power = PowerSnapshot(
        takenAt: evening,
        outages: [
          PowerOutage(customers: 120, start: DateTime(2026, 10, 27, 22), lat: 48.405, lon: -71.174),
        ],
      );
      final place = livePlace(maman);
      final alerts = OutageAlerts.due(place, CityData(power: power), evening, who: 'Chez maman');
      expect(alerts.single.title, 'Chez maman : panne de courant');
      expect(
        OutageAlerts.due(place, CityData(power: power), evening, alreadySent: {alerts.single.key}),
        isEmpty,
      );
    });
  });

  group('toutes les alertes d’un coup', () {
    final power = PowerSnapshot(
      takenAt: evening,
      outages: [
        PowerOutage(customers: 120, start: DateTime(2026, 10, 27, 22), lat: 48.405, lon: -71.174),
      ],
    );
    final city = CityData(power: power);
    final mamanPlace = livePlace(maman);

    test('un proche suivi : eau et pannes seulement, sous son nom', () {
      final all = Alerts.due(
        racine,
        city,
        evening,
        enabled: ReminderKind.values.toSet(),
        followed: [(place: mamanPlace, who: 'Chez maman')],
      );
      expect(all.map((a) => a.title), contains('Chez maman : panne de courant'));
    });

    test('ce qui est désactivé ne sort pas', () {
      final none = Alerts.due(
        racine,
        city,
        evening,
        enabled: {ReminderKind.water},
        followed: [(place: mamanPlace, who: 'Chez maman')],
      );
      expect(none, isEmpty);
    });

    test('l’adresse affichée n’est pas signalée deux fois', () {
      final mine = Alerts.due(
        mamanPlace,
        city,
        evening,
        enabled: {ReminderKind.power},
        followed: [(place: mamanPlace, who: 'Chez maman')],
      );
      expect(mine.single.title, 'Panne de courant dans ton secteur');
    });
  });

  group('la journée en un texto', () {
    test('court, sans symboles, avec la prochaine collecte', () {
      final text = DaySummary.text(racine, Demo.city, DateTime(2026, 10, 26, 19, 30));
      expect(text.length, lessThanOrEqualTo(DaySummary.maxLength));
      expect(text, startsWith('201, rue Racine Est : '));
      expect(text, isNot(contains('..')));
      expect(text, isNot(contains('·')));
    });

    test('le nom d’un proche remplace l’adresse', () {
      final text = DaySummary.text(
        racine,
        Demo.city,
        DateTime(2026, 10, 26, 19, 30),
        name: 'Chez maman',
      );
      expect(text, startsWith('Chez maman : '));
    });

    test('la collecte déjà en tête n’est pas répétée', () {
      final text = DaySummary.text(
        Demo.place('saint-pierre'),
        const CityData(),
        DateTime(2026, 8, 12, 14),
      );
      expect(text, contains('Recyclage, demain.'));
      expect(text, isNot(contains('Prochaine collecte')));
    });

    test('rien à signaler le dit simplement', () {
      final empty = livePlace(
        const ResolvedAddress(
          civic: '1',
          street: 'Rue Test',
          sector: 'Chicoutimi',
          lat: 48.42,
          lon: -71.06,
        ),
      );
      expect(
        DaySummary.text(empty, const CityData(), DateTime(2026, 8, 12, 14)),
        startsWith('1, rue Test : rien de spécial pour l’instant.'),
      );
    });
  });
}
