import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

void main() {
  const engine = RelevanceEngine();
  final racine = Demo.place('racine');
  final at735 = DateTime(2026, 11, 18, 7, 35);

  // Le 105 de 7 h 46, voyage T105.
  Place withTrips() => Place(
    id: racine.id,
    label: racine.label,
    shortLabel: racine.shortLabel,
    collection: racine.collection,
    stop: StopSchedule(
      name: '150, Racine Est',
      validFrom: DateTime(2026, 10, 24),
      validTo: DateTime(2027, 1, 3),
      byDate: {
        dayNumber(at735): const [
          Departure(466, '105', 'La Baie', tripId: 'T105', stopId: '150'),
          Departure(467, '10', 'UQAC', tripId: 'T10', stopId: '150'),
        ],
      },
    ),
  );

  test('avec le temps réel, le retard est dans la carte', () {
    final rt = TransitRealtime(
      takenAt: at735,
      trips: {
        'T105': {'150': 180},
        'T10': {'150': 0},
      },
    );
    final today = engine.today(withTrips(), CityData(transit: rt), at735);
    final bus = today.signals.firstWhere((s) => s.kind == SignalKind.bus);
    // 7 h 46 + 3 min : le 10 de 7 h 47 passe avant le 105.
    expect(bus.title, 'Le 10 passe dans 12 min');
    expect(bus.body, contains('À l’heure, selon la STS.'));
    expect(bus.body, contains('Ensuite le 105 à 7 h 49.'));
  });

  test('un bus en retard sur l’horaire reste annoncé', () {
    final rt = TransitRealtime(
      takenAt: DateTime(2026, 11, 18, 7, 47),
      trips: {
        'T105': {'150': 300},
      },
    );
    final today = engine.today(withTrips(), CityData(transit: rt), DateTime(2026, 11, 18, 7, 48));
    final bus = today.signals.firstWhere((s) => s.kind == SignalKind.bus);
    expect(bus.title, 'Le 105 passe dans 3 min');
    expect(bus.body, contains('5 min de retard'));
  });

  test('un temps réel trop vieux est ignoré, et le widget n’en tient jamais compte', () {
    final old = TransitRealtime(
      takenAt: DateTime(2026, 11, 18, 7, 20),
      trips: {
        'T105': {'150': 600},
      },
    );
    final today = engine.today(withTrips(), CityData(transit: old), at735);
    expect(
      today.signals.firstWhere((s) => s.kind == SignalKind.bus).title,
      'Le 105 passe dans 11 min',
    );
    final fresh = TransitRealtime(takenAt: at735, trips: old.trips);
    final widget = engine.today(withTrips(), CityData(transit: fresh), at735, fixedTimes: true);
    expect(
      widget.signals.firstWhere((s) => s.kind == SignalKind.bus).title,
      'Le 105 passe à 7 h 46',
    );
  });

  group('routes', () {
    RoadReport report(String surface, String visibility) => RoadReport(
      takenAt: at735,
      segments: [
        RoadSegment(
          route: 175,
          from: 'L’Étape',
          to: 'Saguenay',
          surface: surface,
          visibility: visibility,
        ),
      ],
    );

    test('routes dégagées : une tuile calme', () {
      final today = engine.today(
        racine,
        CityData(roads: report('Dégagée et sèche', 'Bonne')),
        at735,
      );
      final tile = today.tiles.firstWhere((t) => t.kind == SignalKind.roads);
      expect(tile.value, 'Dégagées');
      expect(tile.quiet, isTrue);
    });

    test('chaussée enneigée : une tuile qui se remarque', () {
      final today = engine.today(racine, CityData(roads: report('Enneigée', 'Réduite')), at735);
      final tile = today.tiles.firstWhere((t) => t.kind == SignalKind.roads);
      expect(tile.label, 'Route 175');
      expect(tile.value, 'Enneigée');
      expect(tile.quiet, isFalse);
    });

    test('route glacée : la carte du haut', () {
      final today = engine.today(
        racine,
        CityData(roads: report('Glacée', 'Nulle')),
        DateTime(2026, 11, 18, 8),
      );
      expect(today.hero?.title, 'Route 175 : glacée');
    });
  });

  test('sans horaire de collecte, pas de fausse alerte : une tuile d’attente', () {
    final place = Place(
      id: 'adr:test',
      label: 'Test',
      shortLabel: 'Test',
      collection: const CollectionSchedule({}),
      collectionMissing: true,
    );
    final today = engine.today(place, const CityData(), DateTime(2026, 10, 25, 18));
    expect(today.signals.where((s) => s.kind == SignalKind.collection), isEmpty);
    expect(today.tiles.firstWhere((t) => t.kind == SignalKind.collection).value, 'Horaire à venir');
  });
}
