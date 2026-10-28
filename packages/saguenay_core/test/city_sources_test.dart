import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

// Vraies réponses du 25 octobre 2026, enregistrées dans test/fixtures.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
Map<String, Object?> json(String name) =>
    (jsonDecode(fixture(name)) as Map).cast<String, Object?>();

const racine = (lat: 48.42825, lon: -71.06225);

void main() {
  group('géographie', () {
    final square = [
      [(-71.0, 48.0), (-70.0, 48.0), (-70.0, 49.0), (-71.0, 49.0), (-71.0, 48.0)],
    ];

    test('un point dans une zone, et un point dehors', () {
      expect(insideRings(square, 48.5, -70.5), isTrue);
      expect(insideRings(square, 48.5, -71.5), isFalse);
    });

    test('un trou dans la zone n’en fait pas partie', () {
      final withHole = [
        ...square,
        [(-70.6, 48.4), (-70.4, 48.4), (-70.4, 48.6), (-70.6, 48.6), (-70.6, 48.4)],
      ];
      expect(insideRings(withHole, 48.5, -70.5), isFalse);
      expect(insideRings(withHole, 48.2, -70.5), isTrue);
    });

    test('distance à un tracé, en mètres', () {
      final line = [
        [(-71.0, 48.0), (-71.0, 48.1)],
      ];
      // Un millième de degré de longitude à cette latitude : environ 74 m.
      expect(distanceToPaths(line, 48.05, -71.001), closeTo(74.5, 1.5));
    });

    test('les noms de rue se comparent sans accents ni abréviations', () {
      expect(streetKey('Rue St-Éloi'), streetKey('RUE SAINT-ELOI'));
      expect(streetKey('Boul. du Saguenay'), streetKey('Boulevard du Saguenay'));
      expect(streetKey('Rue Racine Est'), isNot(streetKey('Rue Racine Ouest')));
    });
  });

  group('adresses', () {
    test('le géocodeur du Québec propose des adresses de Saguenay', () {
      final s = parseAddressSuggestions(json('icherche.json'));
      expect(s.first.label, startsWith('201 rue Racine Est, Saguenay'));
      expect(s.first.lat, closeTo(racine.lat, .001));
      expect(s.every((x) => x.label.contains(', Saguenay')), isTrue);
    });

    test('la couche de la Ville donne la rue et le secteur', () {
      final a = parseCityAddress(
        json('adresses_ville.json'),
        civic: '201',
        lat: racine.lat,
        lon: racine.lon,
      )!;
      expect(a.civic, '201');
      expect(a.street, 'Rue Racine Est');
      expect(a.sector, 'Chicoutimi');
      expect(a.label, '201, rue Racine Est');
      expect(a.shortLabel, 'Racine Est');
      expect(sectorNumber(a.sector), 3);
      expect(sectorNumber('JONQUIÈRE'), 7);
      expect(ResolvedAddress.fromJson(a.toJson()).id, a.id);
    });

    test('le numéro civique en tête d’adresse', () {
      expect(civicOf('201 rue Racine Est, Saguenay'), '201');
      expect(civicOf('3100A chemin Saint-Jean'), '3100A');
      expect(civicOf('Rue Racine'), isNull);
    });

    test('client : proposer, puis confirmer auprès de la Ville', () async {
      final client = AddressClient(
        client: MockClient((r) async {
          final name = r.url.host == 'geoegl.msp.gouv.qc.ca'
              ? 'icherche.json'
              : 'adresses_ville.json';
          return http.Response.bytes(utf8.encode(fixture(name)), 200);
        }),
      );
      final suggestions = await client.search('201 racine est');
      final resolved = await client.resolve(suggestions.first);
      expect(resolved?.sector, 'Chicoutimi');
      expect(await client.search('ab'), isEmpty);
    });
  });

  group('collectes de la Ville', () {
    test('le bâtiment, les types de collecte, les prochaines dates', () {
      final rues = decodeCityJson(fixture('collectes_rues.json'));
      expect(parseCollectionBuilding(rues, street: 'Rue Racine Est'), 60164);
      expect(parseCollectionBuilding(rues, street: 'Rue Racine Ouest'), isNull);
      final types = parseCollectionTypes(decodeCityJson(fixture('collectes_infos.json')));
      expect(types, {
        WasteStream.garbage: 292,
        WasteStream.recycling: 303,
        WasteStream.compost: 351,
      });
      expect(
        parseNextCollection(decodeCityJson(fixture('collectes_cedule_303.json'))),
        DateTime(2026, 10, 27),
      );
    });

    test('l’horaire reconstruit est celui du calendrier officiel', () {
      final live = collectionFromNextDates({
        WasteStream.garbage: DateTime(2026, 11, 2),
        WasteStream.recycling: DateTime(2026, 10, 27),
        WasteStream.compost: DateTime(2026, 11, 6),
      });
      final official = Demo.place('racine').collection;
      for (var d = DateTime(2026, 10, 25); d.isBefore(DateTime(2026, 12, 31)); d = addDays(d, 1)) {
        expect(live.on(d), official.on(d), reason: '$d');
      }
    });

    test('client : trois petites requêtes, comme le formulaire', () async {
      final asked = <String>[];
      final client = CollectionClient(
        client: MockClient((r) async {
          final path = r.url.pathSegments.last;
          asked.add(path);
          final body = Uri.splitQueryString(r.body);
          return http.Response.bytes(
            utf8.encode(switch (path) {
              'rues' => fixture('collectes_rues.json'),
              'collectesinfos' => fixture('collectes_infos.json'),
              'cedule' => fixture('collectes_cedule_${body['horaire_id']}.json'),
              _ => '[]',
            }),
            200,
          );
        }),
      );
      const address = ResolvedAddress(
        civic: '201',
        street: 'Rue Racine Est',
        sector: 'Chicoutimi',
        lat: 48.42825,
        lon: -71.06225,
      );
      final schedule = await client.schedule(address);
      expect(schedule.on(DateTime(2026, 10, 27)), [WasteStream.recycling]);
      expect(asked, ['rues', 'collectesinfos', 'cedule', 'cedule', 'cedule']);
    });

    test('client : une adresse inconnue du formulaire lève une erreur claire', () {
      final client = CollectionClient(client: MockClient((_) async => http.Response('[]', 200)));
      const address = ResolvedAddress(
        civic: '9999',
        street: 'Rue Nulle Part',
        sector: 'Chicoutimi',
        lat: 0,
        lon: 0,
      );
      expect(client.schedule(address), throwsFormatException);
    });
  });

  group('avis d’aqueduc en direct', () {
    final notices = parseWaterNotices(json('avis_aqueduc.json'));

    test('les avis levés ou supprimés sont écartés', () {
      final numbers = notices.map((n) => n.number).toSet();
      expect(numbers, contains('2026-378'));
      expect(numbers, isNot(contains('2026-379')));
    });

    test('chaque avis a sa zone, et une adresse dedans est touchée', () {
      final boil = notices.firstWhere((n) => n.number == '2026-378');
      expect(boil.type, WaterNoticeType.boil);
      expect(boil.rings, isNotEmpty);
      // Une grille sur le rectangle de la zone : une partie dedans, une partie dehors.
      final pts = boil.rings.expand((r) => r);
      final lats = pts.map((p) => p.$2), lons = pts.map((p) => p.$1);
      final (s, n) = (lats.reduce((a, b) => a < b ? a : b), lats.reduce((a, b) => a > b ? a : b));
      final (w, e) = (lons.reduce((a, b) => a < b ? a : b), lons.reduce((a, b) => a > b ? a : b));
      var inside = 0;
      for (var i = 1; i < 20; i++) {
        for (var j = 1; j < 20; j++) {
          if (boil.covers(s + (n - s) * i / 20, w + (e - w) * j / 20)) inside++;
        }
      }
      expect(inside, inInclusiveRange(1, 360));
      expect(notices.where((n) => n.covers(racine.lat, racine.lon)), isEmpty);
    });

    test('un relevé survit à un aller-retour en JSON, zones comprises', () {
      final snapshot = WaterSnapshot(takenAt: DateTime(2026, 10, 25, 15), notices: notices);
      final copy = WaterSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>,
      );
      expect(copy.notices.first.rings.first.length, notices.first.rings.first.length);
      expect(copy.knownUntil, DateTime(2026, 10, 26, 3));
    });
  });

  group('travaux en direct', () {
    final works = parseRoadworks(json('travaux.json'));

    test('chaque chantier a son tracé et son secteur', () {
      expect(works, hasLength(36));
      expect(works.every((w) => w.paths.isNotEmpty), isTrue);
      expect(works.first.sector, isNotNull);
    });

    test('les chantiers proches de l’adresse, du plus proche au plus loin', () {
      final snapshot = RoadworkSnapshot(takenAt: DateTime(2026, 10, 25), works: works);
      final near = snapshot.near(racine.lat, racine.lon, street: 'Rue Racine Est');
      final distances = near.map((n) => n.work.distanceTo(racine.lat, racine.lon)).toList();
      expect(distances, orderedEquals([...distances]..sort()));
      expect(distances.every((d) => d < 1500), isTrue);
    });

    test('sur ma rue : même nom de rue à moins de 600 m', () {
      final snapshot = RoadworkSnapshot(
        takenAt: DateTime(2026, 10, 25),
        works: [
          Roadwork(
            street: 'Rue Racine Est',
            shortName: 'Racine Est',
            status: 'fermée',
            details: '',
            start: DateTime(2026),
            end: DateTime(2027),
            paths: const [
              [(-71.0640, 48.4290), (-71.0660, 48.4295)],
            ],
          ),
        ],
      );
      expect(
        snapshot.near(racine.lat, racine.lon, street: 'Rue Racine Est').single.onMyStreet,
        isTrue,
      );
      expect(
        snapshot.near(racine.lat, racine.lon, street: 'Rue Jacques-Cartier').single.onMyStreet,
        isFalse,
      );
    });
  });

  group('bus de la STS', () {
    Uint8List zip() {
      final archive = Archive();
      void add(String name, String text) =>
          archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
      add(
        'stops.txt',
        'stop_id,stop_name,stop_lat,stop_lon\n1,"Racine, boul. Talbot",48.4284,-71.0624\n2,Loin,48.50,-71.20\n3,Racine / Bégin,48.4281,-71.0619\n',
      );
      add(
        'routes.txt',
        'route_id,route_short_name,route_long_name\nR105,105,La Baie\nR10,10,UQAC\n',
      );
      add(
        'trips.txt',
        'route_id,service_id,trip_id,trip_headsign\nR105,S1,T1,La Baie\nR10,S1,T2,UQAC\nR10,S2,T3,UQAC\n',
      );
      add(
        'calendar_dates.txt',
        'service_id,date,exception_type\nS1,20261026,1\nS1,20261027,1\nS2,20261101,1\n',
      );
      add(
        'stop_times.txt',
        'trip_id,arrival_time,departure_time,stop_id,stop_sequence\nT1,07:46:00,07:46:00,1,5\nT2,24:30:00,24:30:00,3,9\nT3,10:17:00,10:17:00,1,2\nT1,08:00:00,08:00:00,2,6\n',
      );
      add(
        'feed_info.txt',
        'feed_publisher_name,feed_start_date,feed_end_date\nConsat,20261024,20270103\n',
      );
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    test('les arrêts les plus proches, des deux côtés de la rue', () {
      final feed = GtfsFeed.parse(zip());
      final stops = feed.nearestStops(racine.lat, racine.lon);
      expect(stops.map((s) => s.id), unorderedEquals(['1', '3']));
      expect(stops.firstWhere((s) => s.id == '1').name, 'Racine, boul. Talbot');
      expect(feed.validTo, DateTime(2027, 1, 3));
    });

    test('l’horaire date par date, jours fériés et départs après minuit compris', () {
      final feed = GtfsFeed.parse(zip());
      final s = feed.schedule(
        feed.nearestStops(racine.lat, racine.lon),
        from: DateTime(2026, 10, 25),
      );
      expect(s.forDay(DateTime(2026, 10, 26)).map((d) => (d.route, d.minute)), [('105', 466)]);
      // T2 part à 24 h 30 le 27 : c'est le 28 à 0 h 30.
      expect(s.forDay(DateTime(2026, 10, 28)).single.minute, 30);
      expect(s.forDay(DateTime(2026, 11, 1)).single.route, '10');
      expect(s.forDay(DateTime(2026, 10, 30)), isEmpty);
      final copy = StopSchedule.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
      );
      expect(copy.forDay(DateTime(2026, 10, 26)).single.tripId, 'T1');
    });

    test('les destinations, comme sur l’afficheur du bus', () {
      expect(cleanHeadsign('Terminus Chioutimi vers Terminus La Baie'), 'La Baie');
      expect(cleanHeadsign('UQAC vers terminus Chicoutimi'), 'Chicoutimi');
      expect(
        cleanHeadsign('La Baie via Chicoutimi via Bagotville'),
        'La Baie via Chicoutimi via Bagotville',
      );
    });

    test('le temps réel de la STS se décode sans bibliothèque protobuf', () {
      final rt = parseTripUpdates(File('test/fixtures/sts_tripupdates.pb').readAsBytesSync());
      expect(rt.trips, isNotEmpty);
      expect(rt.takenAt.year, 2026);
      final delays = rt.trips.values.expand((m) => m.values);
      expect(delays.every((d) => d.abs() < 4 * 3600), isTrue);
    });

    test('un flux tronqué lève une erreur claire', () {
      final bytes = File('test/fixtures/sts_tripupdates.pb').readAsBytesSync();
      expect(() => parseTripUpdates(Uint8List.sublistView(bytes, 0, 50)), throwsFormatException);
    });
  });

  group('routes', () {
    test('seulement les routes suivies, la 175 en premier', () {
      final segments = parseRoadConditions(json('conditions_routieres.json'));
      expect(segments.first.route, 175);
      expect(segments.every((s) => RoadReport.routes.contains(s.route)), isTrue);
      final report = RoadReport(takenAt: DateTime(2026, 10, 25), segments: segments);
      expect(report.worst, isNull);
    });

    test('les caméras renvoient vers Québec 511', () {
      final cameras = parseCameras(json('cameras.json'));
      expect(cameras, isNotEmpty);
      expect(cameras.every((c) => c.url.startsWith('https://www.quebec511.info/')), isTrue);
      final report = RoadReport(
        takenAt: DateTime(2026, 10, 25),
        segments: const [],
        cameras: cameras,
      );
      expect(report.camerasNear(racine.lat, racine.lon, max: 2), hasLength(2));
    });
  });

  test('une vraie adresse avec ses données en direct', () {
    const a = ResolvedAddress(
      civic: '201',
      street: 'Rue Racine Est',
      sector: 'Chicoutimi',
      lat: 48.42825,
      lon: -71.06225,
    );
    final schedule = collectionFromNextDates({WasteStream.recycling: DateTime(2026, 10, 27)});
    final copy = CollectionSchedule.fromJson(
      jsonDecode(jsonEncode(schedule.toJson())) as Map<String, Object?>,
    );
    expect(copy.on(DateTime(2026, 11, 10)), [WasteStream.recycling]);
    final place = livePlace(
      a,
      collection: copy,
      water: WaterSnapshot(
        takenAt: DateTime(2026, 10, 25),
        notices: parseWaterNotices(json('avis_aqueduc.json')),
      ),
      roadworks: RoadworkSnapshot(
        takenAt: DateTime(2026, 10, 25),
        works: parseRoadworks(json('travaux.json')),
      ),
    );
    expect(place.id, a.id);
    expect(place.waterNotices, isEmpty);
    expect(place.roadworks.length, lessThanOrEqualTo(4));
    expect(livePlace(a).collectionMissing, isTrue);
  });
}
