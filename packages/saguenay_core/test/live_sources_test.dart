import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

// Extraits réels du 25 octobre 2026, raccourcis.
const _cityPage = {
  'properties': {
    'lastUpdated': '2026-10-25T19:05:21Z',
    'currentConditions': {
      'temperature': {
        'value': {'en': 18.3, 'fr': 18.3},
      },
    },
    'hourlyForecastGroup': {
      'hourlyForecasts': [
        {
          'condition': {'en': 'Mainly sunny', 'fr': 'Généralement ensoleillé'},
        },
      ],
    },
    'forecastGroup': {
      'forecasts': [
        {
          'period': {
            'textForecastName': {'fr': 'Aujourd\'hui'},
          },
          'textSummary': {'fr': 'Généralement ensoleillé. Maximum 15.'},
        },
        {
          'period': {
            'textForecastName': {'fr': 'Ce soir et cette nuit'},
          },
          'textSummary': {'fr': 'Neige. Accumulation de 10 à 15 cm. Minimum moins 6.'},
        },
      ],
    },
  },
};

Map<String, Object?> _alert(
  String name,
  String type,
  String status, {
  String end = '2026-10-26T12:00:00Z',
}) => {
  'properties': {
    'alert_name_fr': name,
    'alert_type': type,
    'status_en': status,
    'publication_datetime': '2026-10-25T16:21:21.424Z',
    'event_end_datetime': end,
    'alert_text_fr':
        'Neige abondante.\n\nQuoi :\nAccumulation de 15 à 20 cm.\n\nQuand :\nCe soir et cette nuit.',
  },
};

const _outages = '''
{"messages": {}, "pannes": [
  [424, "2026-10-25 13:37:25", "2026-10-25 19:00:00", "P", "[-71.0650, 48.4300]", "L", "5", "54", "1185", ""],
  [12, "2026-10-25 12:13:08", "", "P", "[-72.68296938513723, 45.306271556235934]", "N", "", "", "1508", ""],
  ["oups", "x"],
  [3, "pas une date", "", "P", "[-71, 48]", "N", "", "", "", ""]
]}''';

const _planned = '''
[
  [3, "58236", "2026-10-30 09:00:00", "2026-10-30 13:00:00", "2026-10-30 09:00:00", "2026-10-30 13:00:00", "", "", "", "", "61", "40", "", "94068", "N", "[-70.88653425850242, 48.34108549305573]"],
  [165, "188682", "2026-10-22 08:00:00", "2026-10-22 16:00:00", "2026-10-27 08:00:00", "2026-10-27 16:00:00", "2026-10-27 08:00:00", "2026-10-27 16:00:00", "", "", "62", "10", "44", "78095", "R", "[-74.39, 46.16]"]
]''';

void main() {
  group('Environnement Canada', () {
    test('température, condition de la prochaine heure et neige de la nuit', () {
      final w = parseCityWeather(_cityPage);
      expect(w.temperature, 18.3);
      expect(w.condition, 'Généralement ensoleillé');
      expect(w.snowTonightCm, 15);
      expect(w.takenAt, DateTime.utc(2026, 10, 25, 19, 5, 21).toLocal());
      expect(w.forecast.first, 'Aujourd\'hui : Généralement ensoleillé. Maximum 15.');
      expect(WeatherSnapshot.fromJson(w.toJson()).forecast, w.forecast);
    });

    test('la neige en centimètres, dans les tournures du bulletin', () {
      expect(snowCentimetres('Neige. Accumulation de 15 cm.'), 15);
      expect(snowCentimetres('Averses de neige. Accumulation de 2 à 4 cm.'), 4);
      expect(snowCentimetres('Pluie. Accumulation de 10 mm.'), isNull);
      expect(snowCentimetres('Averses de neige.'), isNull);
    });

    test('alertes : une par nom, sans les terminées, de la plus grave à la plus douce', () {
      final alerts = parseWeatherAlerts({
        'features': [
          _alert('bulletin météorologique spécial', 'statement', 'active'),
          _alert('avertissement de neige', 'warning', 'active'),
          _alert('avertissement de neige', 'warning', 'active'),
          _alert('avertissement de pluie', 'warning', 'ended'),
          _alert('veille de tempête', 'watch', 'active', end: '2026-10-25T10:00:00Z'),
          {'properties': null},
          'n’importe quoi',
        ],
      }, now: DateTime.utc(2026, 10, 25, 20));
      expect(alerts.map((a) => a.name), [
        'Avertissement de neige',
        'Bulletin météorologique spécial',
      ]);
      expect(alerts.first.what, 'Accumulation de 15 à 20 cm.');
      expect(alerts.first.when, 'Ce soir et cette nuit.');
    });

    test('un relevé survit à un aller-retour en JSON', () {
      final w = Demo.moments.firstWhere((m) => m.weather != null).weather!;
      final copy = WeatherSnapshot.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, Object?>,
      );
      expect(copy.alerts.single.name, w.alerts.single.name);
      expect(copy.snowTonightCm, w.snowTonightCm);
      expect(copy.temperature, w.temperature);
    });
  });

  group('Hydro-Québec', () {
    test('pannes : lit ce qui est lisible, ignore le reste', () {
      final outages = parseOutages(_outages);
      expect(outages, hasLength(2));
      expect(outages.first.customers, 424);
      expect(outages.first.end, DateTime(2026, 10, 25, 19));
      expect(outages.first.cause, 'accident ou incident');
      expect(outages[1].end, isNull);
    });

    test('interruptions planifiées : la date reportée l’emporte', () {
      final planned = parsePlannedInterruptions(_planned);
      expect(planned.first.start, DateTime(2026, 10, 30, 9));
      expect(planned.first.planned, isTrue);
      expect(planned[1].start, DateTime(2026, 10, 27, 8));
    });

    test('un fichier inattendu lève une erreur claire', () {
      expect(() => parseOutages('[]'), throwsFormatException);
      expect(() => parsePlannedInterruptions('{}'), throwsFormatException);
    });

    test('le secteur grandit avec le nombre de clients, sans dépasser 8 km', () {
      PowerOutage o(int n) => PowerOutage(customers: n, start: DateTime(2026), lat: 0, lon: 0);
      expect(o(1).radiusKm, closeTo(1.1, .01));
      expect(o(400).radiusKm, 3);
      expect(o(100000).radiusKm, 8);
    });

    test('client : version, puis fichier', () async {
      final asked = <String>[];
      final client = HydroClient(
        client: MockClient((r) async {
          asked.add(r.url.path.split('/').last);
          return switch (r.url.path.split('/').last) {
            'bisversion.json' => http.Response('"20261025150012"', 200),
            'aipversion.json' => http.Response('"20261025150012"', 200),
            'bismarkers20261025150012.json' => http.Response(_outages, 200),
            'aipmarkers20261025150012.json' => http.Response(_planned, 200),
            _ => http.Response('', 404),
          };
        }),
      );
      final snapshot = await client.fetch(now: DateTime(2026, 10, 25, 15));
      expect(snapshot.outages, hasLength(4));
      expect(
        asked,
        containsAll(['bismarkers20261025150012.json', 'aipmarkers20261025150012.json']),
      );
    });

    test('client : un numéro de version douteux n’entre jamais dans une adresse', () {
      final client = HydroClient(
        client: MockClient((r) async => http.Response('"../../autre/chose"', 200)),
      );
      expect(client.fetch(), throwsFormatException);
    });
  });

  group('téléchargements', () {
    test('une réponse trop grosse est refusée', () {
      final client = MockClient((_) async => http.Response('x' * 5000, 200));
      expect(
        download(client, Uri.parse('https://exemple.test/'), maxBytes: 1000),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('un serveur qui ne répond pas finit par abandonner', () {
      final client = MockClient((_) => Completer<http.Response>().future);
      expect(
        download(
          client,
          Uri.parse('https://exemple.test/'),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('relevé du MSSS', () {
    const header =
        'Nom_installation,No_permis_installation,Nombre_de_civieres_fonctionnelles,'
        'Nombre_de_civieres_occupees,Nombre_total_de_patients_presents_a_lurgence,'
        'Nombre_total_de_patients_en_attente_de_PEC,Mise_a_jour\n';

    test('un fichier sans les urgences de Saguenay est refusé', () {
      expect(
        () => parseMsssHourly('${header}HÔPITAL D’ALMA,51219400,17,8,17,6,2026-10-25T6:45\n'),
        throwsFormatException,
      );
    });

    test('une installation répétée : la ligne la plus récente gagne', () {
      final s = parseMsssHourly(
        '$header'
        'HÔPITAL DE CHICOUTIMI,51218394,41,30,40,2,2026-10-25T9:45\n'
        'HÔPITAL DE CHICOUTIMI,51218394,41,34,40,2,2026-10-25T6:45\n',
      );
      expect(s.rooms.single.occupied, 30);
      expect(s.takenAt, DateTime(2026, 10, 25, 9, 45));
    });
  });

  test('l’heure d’un relevé dit le jour quand ce n’est pas aujourd’hui', () {
    final now = DateTime(2026, 10, 27, 9);
    expect(takenLabel(DateTime(2026, 10, 27, 8, 5), now), 'de 8 h 05');
    expect(takenLabel(DateTime(2026, 10, 26, 15, 41), now), 'd’hier à 15 h 41');
    expect(takenLabel(DateTime(2026, 10, 24, 15), now), 'du samedi 24 oct. à 15 h');
  });
}
