import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

void main() {
  const engine = RelevanceEngine();
  Today at(String place, DateTime t) => engine.today(Demo.place(place), Demo.city, t);

  test('dimanche soir de novembre : le stationnement passe avant le bac', () {
    final today = at('racine', DateTime(2026, 11, 15, 21, 30));
    expect(today.hero?.kind, SignalKind.parking);
    expect(today.hero?.title, 'Pas d’auto dans la rue cette nuit');
    expect(today.signals[1].title, 'Sors le bac à ordures');
    expect(today.signals[1].score, 65);
  });

  test('un avis d’ébullition passe avant tout et demande une notification', () {
    final today = at('saint-jean', DateTime(2026, 10, 25, 7, 10));
    expect(today.hero?.kind, SignalKind.water);
    expect(today.hero?.critical, isTrue);
    expect(today.hero?.notify, isTrue);
    expect(today.hero?.score, 100);
  });

  test('veille de collecte : le bac bleu, avec les travaux à côté', () {
    final today = at('racine', DateTime(2026, 10, 26, 19, 30));
    expect(today.hero?.title, 'Sors le bac bleu');
    expect(today.tiles.first.kind, SignalKind.roadwork);
  });

  test('trois chantiers sur une même rue : une seule tuile, la plus contraignante', () {
    Roadwork work(String status) => Roadwork(
      street: 'Boulevard Saguenay Est',
      shortName: 'Saguenay Est',
      status: status,
      details: 'Travaux d’aqueduc.',
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 12, 1),
    );
    final place = Place(
      id: 'tache',
      label: '517, rue Taché',
      shortLabel: 'Taché',
      collection: const CollectionSchedule({}),
      roadworks: [
        NearbyRoadwork(work('à contresens'), onMyStreet: false),
        NearbyRoadwork(work('fermée'), onMyStreet: true),
        NearbyRoadwork(work('fermée'), onMyStreet: false),
      ],
    );
    final today = engine.today(place, const CityData(), DateTime(2026, 10, 28, 18, 15));
    final works = today.signals.where((s) => s.kind == SignalKind.roadwork).toList();
    expect(works, hasLength(1));
    expect(works.single.title, 'Boulevard Saguenay Est, fermée');
    expect(works.single.body, '3 chantiers sur cette rue. Travaux d’aqueduc.');
    // En haut ou en tuile, la rue n'apparaît qu'une fois.
    final shown = [?today.hero?.kind, ...today.tiles.map((t) => t.kind)];
    expect(shown.where((k) => k == SignalKind.roadwork), hasLength(1));
  });

  test('en semaine à 7 h 35 : le prochain bus de l’arrêt favori', () {
    final today = at('racine', DateTime(2026, 11, 18, 7, 35));
    expect(today.hero?.title, 'Le 105 passe dans 11 min');
    expect(today.hero?.body, 'Vers La Baie, à 7 h 46. Ensuite le 10 à 7 h 47.');
  });

  test('la veille du 15 novembre : première nuit', () {
    final today = at('racine', DateTime(2026, 11, 14, 21, 30));
    expect(today.hero?.title, 'Première nuit sans auto dans la rue');
  });

  test('travaux sur ma rue à l’heure de pointe', () {
    final today = at('saint-pierre', DateTime(2026, 10, 26, 7, 20));
    expect(today.hero?.title, 'Rue Saint-Pierre, circulation locale');
    expect(today.hero?.label, 'Sur ta route');
  });

  test('journée calme : pas de carte du haut, mais des tuiles rassurantes', () {
    final today = at('saint-jean', DateTime(2026, 11, 5, 12));
    expect(today.hero, isNull);
    expect(
      today.tiles.where((t) => t.quiet).map((t) => t.kind),
      containsAll([SignalKind.water, SignalKind.emergency]),
    );
  });

  test('un avis sans date de fin n’est plus affiché après le relevé', () {
    final today = at('saint-jean', DateTime(2026, 11, 5, 12));
    expect(today.signals.where((s) => s.kind == SignalKind.water), isEmpty);
  });

  test('la carte des urgences ne monte jamais d’elle-même', () {
    for (final moment in Demo.moments) {
      final today = at(moment.placeId, moment.at);
      expect(today.hero?.kind, isNot(SignalKind.emergency));
    }
  });

  group('timeline du widget', () {
    final racine = Demo.place('racine');
    final from = DateTime(2026, 11, 15, 21, 40, 12);
    final entries = engine.timeline(racine, Demo.city, from);

    test('commence à la minute près et couvre sept jours', () {
      expect(entries.first.at, DateTime(2026, 11, 15, 21, 40));
      expect(entries.first.toJson()['title'], 'Pas d’auto dans la rue cette nuit');
      expect(entries.last.at.isAfter(from.add(const Duration(days: 6))), isTrue);
    });

    test('une entrée par changement, dans l’ordre', () {
      for (var i = 1; i < entries.length; i++) {
        expect(entries[i].at.isAfter(entries[i - 1].at), isTrue);
        expect(entries[i].contentKey, isNot(entries[i - 1].contentKey));
      }
    });

    test('aucun texte qui vieillit mal', () {
      for (final e in entries) {
        final json = e.toJson();
        for (final key in ['title', 'body', 'second', 'secondDetail']) {
          expect('${json[key]}', isNot(matches(RegExp(r'dans \d'))), reason: '${e.at} $key');
        }
      }
    });

    test('le bus de 7 h 46 laisse sa place à 7 h 47 pile', () {
      final morning = engine.timeline(racine, Demo.city, DateTime(2026, 11, 18, 7, 30));
      final bus = morning.firstWhere((e) => e.toJson()['title'] == 'Le 105 passe à 7 h 46');
      final next = morning[morning.indexOf(bus) + 1];
      expect(next.at, DateTime(2026, 11, 18, 7, 47));
    });

    test('la nuit du passage à l’heure normale ne casse rien', () {
      final night = engine.timeline(racine, Demo.city, DateTime(2026, 10, 31, 22));
      for (var i = 1; i < night.length; i++) {
        expect(night[i].at.isAfter(night[i - 1].at), isTrue);
      }
    });

    test('se calcule vite', () {
      final watch = Stopwatch()..start();
      engine.timeline(racine, Demo.city, DateTime(2026, 11, 16, 6));
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });
  });

  test('avec des heures fixes, le bus donne l’heure plutôt qu’un compte à rebours', () {
    final today = engine.today(
      Demo.place('racine'),
      Demo.city,
      DateTime(2026, 11, 18, 7, 35),
      fixedTimes: true,
    );
    expect(today.hero?.title, 'Le 105 passe à 7 h 46');
    expect(today.hero?.body, 'Vers La Baie. Ensuite le 10 à 7 h 47.');
  });

  test('un avis d’ébullition n’est pas caché par une coupure annoncée', () {
    const place = Place(
      id: 'test',
      label: 'Test',
      shortLabel: 'Test',
      collection: CollectionSchedule({}),
      waterNotices: ['2026-376', '2026-378'],
    );
    final today = engine.today(place, Demo.city, DateTime(2026, 10, 25, 18));
    expect(today.hero?.critical, isTrue);
    expect(today.hero?.score, 100);
  });

  group('météo', () {
    final racine = Demo.place('racine');
    final storm = Demo.moments.firstWhere((m) => m.weather != null);
    CityData withWeather(WeatherSnapshot w) => CityData(
      waterNotices: Demo.waterNotices,
      waterKnownUntil: Demo.city.waterKnownUntil,
      weather: w,
    );

    test('un avertissement de neige passe en premier, avant le bus', () {
      final today = engine.today(racine, withWeather(storm.weather!), storm.at);
      expect(today.hero?.kind, SignalKind.weather);
      expect(today.hero?.title, 'Avertissement de neige');
      expect(today.hero?.body, 'Accumulation de 15 à 20 cm.');
      expect(today.hero?.notify, isTrue);
    });

    test('de la neige annoncée cette nuit, sans alerte', () {
      final w = WeatherSnapshot(
        takenAt: DateTime(2026, 11, 3, 16),
        temperature: -1,
        snowTonightCm: 8,
      );
      final evening = engine.today(racine, withWeather(w), DateTime(2026, 11, 3, 19));
      expect(evening.signals.first.title, 'Jusqu’à 8 cm de neige');
      final nextDay = engine.today(racine, withWeather(w), DateTime(2026, 11, 4, 9));
      expect(nextDay.signals.where((s) => s.kind == SignalKind.weather), isEmpty);
    });

    test('par beau temps, une tuile calme avec la température', () {
      final w = WeatherSnapshot(
        takenAt: DateTime(2026, 10, 25, 14),
        temperature: 14.6,
        condition: 'Généralement ensoleillé',
      );
      final today = engine.today(racine, withWeather(w), DateTime(2026, 10, 25, 15));
      final tile = today.tiles.firstWhere((t) => t.kind == SignalKind.weather);
      expect(tile.value, '15°');
      expect(tile.detail, 'généralement ensoleillé');
      expect(tile.quiet, isTrue);
    });

    test('une température trop vieille ne s’affiche plus', () {
      final w = WeatherSnapshot(takenAt: DateTime(2026, 10, 25, 6), temperature: 3);
      final today = engine.today(racine, withWeather(w), DateTime(2026, 10, 25, 15));
      expect(today.tiles.where((t) => t.kind == SignalKind.weather), isEmpty);
    });
  });

  group('électricité', () {
    final racine = Demo.place('racine');
    CityData withPower(List<PowerOutage> outages) => CityData(
      power: PowerSnapshot(takenAt: DateTime(2026, 10, 25, 14), outages: outages),
    );

    test('une panne dans le secteur, avec l’heure de retour', () {
      final today = engine.today(
        racine,
        withPower([
          PowerOutage(
            customers: 420,
            start: DateTime(2026, 10, 25, 13, 37),
            end: DateTime(2026, 10, 25, 19),
            lat: 48.4300,
            lon: -71.0650,
            cause: 'conditions météo',
          ),
        ]),
        DateTime(2026, 10, 25, 14, 10),
      );
      expect(today.hero?.title, 'Panne dans ton secteur');
      expect(today.hero?.body, 'Retour du courant prévu vers 19 h.');
      expect(today.hero?.why, contains('420 clients'));
    });

    test('une panne à Jonquière ne concerne pas le centre-ville de Chicoutimi', () {
      final today = engine.today(
        racine,
        withPower([
          PowerOutage(
            customers: 30,
            start: DateTime(2026, 10, 25, 13),
            lat: 48.4168,
            lon: -71.2497,
          ),
        ]),
        DateTime(2026, 10, 25, 14, 10),
      );
      expect(today.signals.where((s) => s.kind == SignalKind.power), isEmpty);
    });

    test('une coupure planifiée demain', () {
      final moment = Demo.moments.firstWhere((m) => m.power != null);
      final today = engine.today(racine, CityData(power: moment.power), moment.at);
      final power = today.signals.firstWhere((s) => s.kind == SignalKind.power);
      expect(power.label, 'Demain');
      expect(power.title, 'Courant coupé de 9 h à 13 h');
    });
  });

  test('après le 31 décembre, on attend le calendrier 2027', () {
    final today = at('racine', DateTime(2027, 1, 2, 10));
    final collection = today.signals.firstWhere((s) => s.kind == SignalKind.collection);
    expect(collection.title, 'Le calendrier 2027 n’est pas encore sorti');
  });
}
