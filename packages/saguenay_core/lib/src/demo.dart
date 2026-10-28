import 'collection.dart';
import 'emergency.dart';
import 'place.dart';
import 'power.dart';
import 'relevance.dart';
import 'roadwork.dart';
import 'transit.dart';
import 'water.dart';
import 'weather.dart';

/// Un moment à rejouer pendant une démo.
///
/// La plupart reprennent les données réelles du relevé. Ceux qui ont une
/// météo ou une panne sont des mises en situation, et le disent.
class DemoMoment {
  const DemoMoment(this.label, this.placeId, this.at, {this.weather, this.power});

  final String label;
  final String placeId;
  final DateTime at;
  final WeatherSnapshot? weather;
  final PowerSnapshot? power;

  bool get isScenario => weather != null || power != null;
}

/// Les vraies données relevées le 25 octobre 2026, pour faire tourner l'app
/// sans réseau. Seuls les calendriers de collecte du chemin Saint-Jean et de
/// la rue Saint-Pierre sont inventés.
abstract final class Demo {
  static final takenAt = DateTime(2026, 10, 25, 6, 45);

  static final waterNotices = <WaterNotice>[
    WaterNotice(
      number: '2026-378',
      type: WaterNoticeType.boil,
      start: DateTime(2026, 10, 24, 17, 13),
      zone:
          'Chemin Saint-Jean (2522 à 4483), route du Petit-Parc, chemin Saint-Antoine, sentier Bourget',
    ),
    WaterNotice(
      number: '2026-376',
      type: WaterNoticeType.interruption,
      start: DateTime(2026, 10, 26, 8),
      end: DateTime(2026, 10, 26, 15),
      zone: '1re Avenue et 2e Rue, entre l’avenue Médéric-Gravel et la 2e Avenue',
    ),
    WaterNotice(
      number: '2026-377',
      type: WaterNoticeType.interruption,
      start: DateTime(2026, 10, 23, 14, 32),
      end: DateTime(2026, 10, 23, 18),
      zone: 'Rues Verdun, Saint-Éloi, Bon-Air et Lajeunesse',
    ),
    WaterNotice(
      number: '2026-373',
      type: WaterNoticeType.interruption,
      start: DateTime(2026, 10, 22, 20),
      end: DateTime(2026, 10, 23, 6),
      zone: 'Boul. du Royaume Ouest, rue Antonio-Lemaire, boul. Saint-Paul',
    ),
    WaterNotice(
      number: '2026-375',
      type: WaterNoticeType.interruption,
      start: DateTime(2026, 10, 22, 8, 30),
      end: DateTime(2026, 10, 22, 16),
      zone: 'Rue Bégin, du 1222 au 1370',
    ),
    WaterNotice(
      number: '2026-367',
      type: WaterNoticeType.discolored,
      start: DateTime(2026, 10, 19, 8),
      end: DateTime(2026, 10, 23, 17),
      zone: 'Secteur de Bagotville',
    ),
  ];

  static final emergencies = EmergencySnapshot(
    takenAt: takenAt,
    rooms: const [
      EmergencyRoom(
        permit: '51218394',
        hospital: 'Chicoutimi',
        occupied: 34,
        functional: 41,
        present: 40,
        waiting: 2,
      ),
      EmergencyRoom(
        permit: '51224541',
        hospital: 'Jonquière',
        occupied: 9,
        functional: 16,
        present: 17,
        waiting: 10,
      ),
      EmergencyRoom(
        permit: '51221364',
        hospital: 'La Baie',
        occupied: 4,
        functional: 7,
        present: 6,
        waiting: 2,
      ),
    ],
  );

  static final city = CityData(
    waterNotices: waterNotices,
    waterKnownUntil: DateTime(2026, 10, 26, 23, 59),
    emergencies: emergencies,
  );

  static final _saguenayEst = Roadwork(
    street: 'Boul. du Saguenay Est',
    shortName: 'Saguenay Est',
    status: 'à contresens',
    details: 'Direction ouest, entre Morin et de l’Hôtel-de-Ville, jusqu’au 6 novembre.',
    start: DateTime(2026, 10, 5, 7),
    end: DateTime(2026, 11, 6, 12),
  );
  static final _sainteMarie = Roadwork(
    street: 'Rue Sainte-Marie Sud',
    shortName: 'Sainte-Marie Sud',
    status: 'fermée',
    details: 'Entre Monseigneur-Martel et Roussel. Détour par Saint-Armand.',
    start: DateTime(2026, 9, 8, 7),
    end: DateTime(2026, 11, 13, 17),
  );
  static final _saintPierre = Roadwork(
    street: 'Rue Saint-Pierre',
    shortName: 'Saint-Pierre',
    status: 'circulation locale',
    details: 'De 7 h à 17 h, entre Saint-Vallier et de Montfort. Passe par le boulevard Harvey.',
    start: DateTime(2026, 10, 20, 7),
    end: DateTime(2026, 10, 27, 17),
    dailyFromMinute: 7 * 60,
    dailyToMinute: 17 * 60,
  );
  static final _chateauguay = Roadwork(
    street: 'Rue Châteauguay',
    shortName: 'Châteauguay',
    status: 'en alternance',
    details: 'Entre Hémon et de la Faïence, avec signaleurs, de 7 h à 17 h.',
    start: DateTime(2026, 10, 26, 7),
    end: DateTime(2026, 10, 26, 17),
  );

  /// Arrêt 150, Racine Est, horaire du flux GTFS de la STS (24 oct. 2026 au 3 janv. 2027).
  static final _racineStop = StopSchedule(
    name: '150, Racine Est',
    weekday: _departures(const [
      ('06:46', '105', 'La Baie'),
      ('06:47', '10', 'UQAC'),
      ('07:16', '106', 'La Baie par Bagotville'),
      ('07:17', '10', 'UQAC'),
      ('07:46', '105', 'La Baie'),
      ('07:47', '10', 'UQAC'),
      ('08:16', '106', 'La Baie par Bagotville'),
      ('08:17', '10', 'UQAC'),
      ('08:47', '10', 'UQAC'),
      ('09:17', '10', 'UQAC'),
      ('09:47', '10', 'UQAC'),
      ('10:17', '10', 'UQAC'),
      ('10:47', '10', 'UQAC'),
      ('11:17', '10', 'UQAC'),
      ('11:47', '10', 'UQAC'),
      ('12:17', '10', 'UQAC'),
      ('12:47', '10', 'UQAC'),
      ('13:17', '10', 'UQAC'),
      ('13:47', '10', 'UQAC'),
      ('14:17', '10', 'UQAC'),
      ('14:47', '10', 'UQAC'),
      ('15:16', '106', 'La Baie par Bagotville'),
      ('15:17', '10', 'UQAC'),
      ('15:46', '105', 'La Baie'),
      ('15:47', '10', 'UQAC'),
      ('16:16', '106', 'La Baie par Bagotville'),
      ('16:17', '10', 'UQAC'),
      ('16:46', '105', 'La Baie'),
      ('16:47', '10', 'UQAC'),
      ('17:16', '106', 'La Baie par Bagotville'),
      ('17:17', '10', 'UQAC'),
      ('17:46', '105', 'La Baie'),
      ('17:47', '10', 'UQAC'),
      ('18:17', '10', 'UQAC'),
      ('19:17', '10', 'UQAC'),
      ('20:17', '10', 'UQAC'),
      ('21:17', '10', 'UQAC'),
      ('22:17', '10', 'UQAC'),
    ]),
    saturday: [for (var h = 7; h <= 18; h++) Departure(h * 60 + 17, '10', 'UQAC')],
    sunday: [for (var h = 8; h <= 17; h++) Departure(h * 60 + 17, '10', 'UQAC')],
    validFrom: DateTime(2026, 10, 24),
    validTo: DateTime(2027, 1, 3),
  );

  static final places = <Place>[
    Place(
      id: 'racine',
      label: '201, rue Racine Est',
      shortLabel: 'Racine Est',
      sector: 'Chicoutimi',
      collection: CollectionSchedule({
        WasteStream.garbage: CollectionRule(
          weekday: DateTime.monday,
          anchor: DateTime(2026, 11, 2),
        ),
        WasteStream.recycling: CollectionRule(
          weekday: DateTime.tuesday,
          anchor: DateTime(2026, 10, 27),
        ),
        WasteStream.compost: CollectionRule(
          weekday: DateTime.friday,
          anchor: DateTime(2026, 11, 6),
          weeklyInSummer: true,
        ),
      }, publishedThrough: DateTime(2026, 12, 31)),
      stop: _racineStop,
      lat: 48.4283,
      lon: -71.0622,
      roadworks: [
        NearbyRoadwork(_saguenayEst, onMyStreet: true),
        NearbyRoadwork(_sainteMarie, onMyStreet: false),
      ],
    ),
    Place(
      id: 'saint-jean',
      label: '3100, chemin Saint-Jean',
      shortLabel: 'Ch. Saint-Jean',
      sector: 'La Baie',
      collectionIsExample: true,
      collection: CollectionSchedule({
        WasteStream.garbage: CollectionRule(
          weekday: DateTime.thursday,
          anchor: DateTime(2026, 10, 29),
        ),
        WasteStream.recycling: CollectionRule(
          weekday: DateTime.wednesday,
          anchor: DateTime(2026, 11, 4),
        ),
        WasteStream.compost: CollectionRule(
          weekday: DateTime.monday,
          anchor: DateTime(2026, 11, 2),
          weeklyInSummer: true,
        ),
      }, publishedThrough: DateTime(2026, 12, 31)),
      waterNotices: const ['2026-378'],
      lat: 48.3147,
      lon: -70.8660,
    ),
    Place(
      id: 'saint-pierre',
      label: 'Rue Saint-Pierre, Jonquière',
      shortLabel: 'Saint-Pierre',
      sector: 'Jonquière',
      collectionIsExample: true,
      collection: CollectionSchedule({
        WasteStream.garbage: CollectionRule(
          weekday: DateTime.wednesday,
          anchor: DateTime(2026, 10, 28),
        ),
        WasteStream.recycling: CollectionRule(
          weekday: DateTime.thursday,
          anchor: DateTime(2026, 11, 5),
        ),
        WasteStream.compost: CollectionRule(
          weekday: DateTime.tuesday,
          anchor: DateTime(2026, 10, 27),
          weeklyInSummer: true,
        ),
      }, publishedThrough: DateTime(2026, 12, 31)),
      // Approximatif : le milieu du tronçon en travaux.
      lat: 48.4168,
      lon: -71.2497,
      roadworks: [
        NearbyRoadwork(_saintPierre, onMyStreet: true),
        NearbyRoadwork(_chateauguay, onMyStreet: false),
      ],
    ),
  ];

  static Place place(String id) => places.firstWhere((p) => p.id == id, orElse: () => places.first);

  static final moments = <DemoMoment>[
    DemoMoment('Dimanche soir en novembre', 'racine', DateTime(2026, 11, 15, 21, 30)),
    DemoMoment('Avis d’ébullition, ce matin', 'saint-jean', DateTime(2026, 10, 25, 7, 10)),
    DemoMoment('Veille de collecte', 'racine', DateTime(2026, 10, 26, 19, 30)),
    DemoMoment('En partant travailler', 'racine', DateTime(2026, 11, 18, 7, 35)),
    DemoMoment('Première nuit d’hiver', 'racine', DateTime(2026, 11, 14, 21, 30)),
    DemoMoment('Travaux dans ma rue', 'saint-pierre', DateTime(2026, 10, 26, 7, 20)),
    DemoMoment(
      'Tempête annoncée (mise en situation)',
      'racine',
      DateTime(2026, 11, 18, 18, 30),
      weather: WeatherSnapshot(
        takenAt: DateTime(2026, 11, 18, 17, 15),
        temperature: -4,
        condition: 'Neige faible',
        snowTonightCm: 20,
        alerts: [
          WeatherAlert(
            name: 'Avertissement de neige',
            level: WeatherAlertLevel.warning,
            issuedAt: DateTime(2026, 11, 18, 15, 40),
            what: 'Accumulation de 15 à 20 cm.',
            when: 'Ce soir et cette nuit.',
            endsAt: DateTime(2026, 11, 19, 12),
          ),
        ],
      ),
    ),
    DemoMoment(
      'Coupure de courant demain (mise en situation)',
      'racine',
      DateTime(2026, 10, 29, 19, 30),
      power: PowerSnapshot(
        takenAt: DateTime(2026, 10, 29, 19),
        outages: [
          PowerOutage(
            customers: 240,
            start: DateTime(2026, 10, 30, 9),
            end: DateTime(2026, 10, 30, 13),
            lat: 48.4291,
            lon: -71.0605,
            planned: true,
          ),
        ],
      ),
    ),
  ];

  static List<Departure> _departures(List<(String, String, String)> rows) => [
    for (final (time, route, headsign) in rows)
      Departure(
        int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3)),
        route,
        headsign,
      ),
  ];
}
