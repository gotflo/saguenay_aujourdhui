import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saguenay_aujourdhui/background/background_refresh.dart';
import 'package:saguenay_aujourdhui/features/assistant/assistant_screen.dart';
import 'package:saguenay_aujourdhui/features/assistant/remote_assistant.dart';
import 'package:saguenay_aujourdhui/features/details/detail_sheet.dart';
import 'package:saguenay_aujourdhui/features/today/today_screen.dart';
import 'package:saguenay_aujourdhui/features/report/report_screen.dart';
import 'package:saguenay_aujourdhui/state/addresses.dart';
import 'package:saguenay_aujourdhui/state/live_sources.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

// Les vraies réponses enregistrées pour les tests du cœur.
String fixture(String name) =>
    File('../packages/saguenay_core/test/fixtures/$name').readAsStringSync();

http.Client addressServer() => MockClient((r) async {
  final name = r.url.host == 'geoegl.msp.gouv.qc.ca' ? 'icherche.json' : 'adresses_ville.json';
  return http.Response.bytes(utf8.encode(fixture(name)), 200);
});

const racineAddress = ResolvedAddress(
  civic: '201',
  street: 'Rue Racine Est',
  sector: 'Chicoutimi',
  lat: 48.42836,
  lon: -71.06223,
);

final racineSchedule = collectionFromNextDates({
  WasteStream.garbage: DateTime(2026, 11, 2),
  WasteStream.recycling: DateTime(2026, 10, 27),
  WasteStream.compost: DateTime(2026, 11, 6),
});

List<Override> liveAddress({Future<CollectionSchedule> Function(ResolvedAddress)? collections}) => [
  addressClientProvider.overrideWithValue(AddressClient(client: addressServer())),
  collectionFetchProvider.overrideWithValue(collections ?? (_) async => racineSchedule),
  gtfsFetchProvider.overrideWithValue(() async => throw Exception('pas de flux dans les tests')),
];

class FakeRemote implements RemoteAssistant {
  final asked = <(String, Map<String, Object?>)>[];
  final explained = <String>[];

  @override
  bool get available => true;

  @override
  Future<String> ask(String question, Map<String, Object?> context) async {
    asked.add((question, context));
    return 'Réponse de l’assistant en ligne.';
  }

  @override
  Future<String> sortPhoto(Uint8List jpeg) async => 'Une canette : le bac bleu.';

  @override
  Future<String> explain(String text) async {
    explained.add(text);
    return 'Beaucoup de neige cette nuit : prévois du temps demain matin.';
  }

  @override
  Future<List<PressNote>> pressReleases() async => [
    PressNote(
      title: 'Ponceau partiellement affaissé rang St-Martin',
      date: DateTime(2026, 10, 5),
      url: Uri.parse('https://ville.saguenay.ca/files/medias/communiques/2026/261005.pdf'),
      summary: 'Une voie du rang Saint-Martin est fermée le temps des réparations.',
    ),
    PressNote(
      title: 'Bilan de la saison de pavage 2026',
      date: DateTime(2026, 9, 29),
      url: Uri.parse('https://ville.saguenay.ca/files/medias/communiques/2026/261006.pdf'),
    ),
  ];
}

void main() {
  testWidgets('chercher une vraie adresse, la choisir, voir son horaire de la Ville', (
    tester,
  ) async {
    await pumpApp(tester, at: DateTime(2026, 10, 26, 19, 30), extra: liveAddress());
    await tester.enterText(find.byType(TextField), '201 racine est');
    await tester.pump(const Duration(milliseconds: 400));
    // Le faux serveur HTTP a besoin d'un vrai tour de boucle.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    expect(find.text('201 rue Racine Est'), findsOneWidget);

    await tester.ensureVisible(find.text('201 rue Racine Est'));
    await tester.pump();
    await tester.tap(find.text('201 rue Racine Est'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
    expect(find.text('201, rue Racine Est'), findsOneWidget);
    expect(find.text('Sors le bac bleu'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('adresses'), hasLength(1));
    expect(prefs.getString('place'), racineAddress.id);
    expect(prefs.getString('collecte:${racineAddress.id}'), isNotNull);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('sans réseau au premier lancement : une tuile d’attente, pas une fausse date', (
    tester,
  ) async {
    await pumpApp(
      tester,
      prefs: {
        'adresses': [jsonEncode(racineAddress.toJson())],
        'place': racineAddress.id,
      },
      extra: liveAddress(collections: (_) async => throw Exception('pas de réseau')),
    );
    expect(find.text('Horaire à venir'), findsOneWidget);
  });

  testWidgets('un avis d’ébullition en direct dont la zone couvre l’adresse', (tester) async {
    final boil = WaterNotice(
      number: '2026-400',
      type: WaterNoticeType.boil,
      start: DateTime(2026, 11, 15, 8),
      zone: 'Centre-ville de Chicoutimi',
      rings: const [
        [(-71.07, 48.42), (-71.05, 48.42), (-71.05, 48.44), (-71.07, 48.44), (-71.07, 48.42)],
      ],
    );
    final notifications = await pumpApp(
      tester,
      prefs: {
        'adresses': [jsonEncode(racineAddress.toJson())],
        'place': racineAddress.id,
      },
      water: WaterStatus(WaterSnapshot(takenAt: sundayEvening, notices: [boil]), SourceOrigin.live),
      extra: liveAddress(),
    );
    await settle(tester);
    expect(find.text('Fais bouillir l’eau avant de la boire'), findsOneWidget);
    expect(notifications.waterAlerts.single.notice.number, '2026-400');
  });

  testWidgets('heures calmes : l’alerte météo de 23 h attend 7 h', (tester) async {
    final storm = Demo.moments.firstWhere((m) => m.weather != null);
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 18, 23),
      weather: WeatherStatus(storm.weather, SourceOrigin.live),
      prefs: {'heures-calmes': true},
    );
    expect(notifications.alerts, isEmpty);
    expect(notifications.deferred.single.$2, DateTime(2026, 11, 19, 7));
  });

  testWidgets('demande à l’app : le tri d’après les pages de la Ville', (tester) async {
    await pumpApp(tester, place: 'racine');
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await settle(tester);
    expect(find.byType(AssistantScreen), findsOneWidget);
    await tester.tap(find.text('Ça va où, une boîte de pizza ?'));
    await settle(tester);
    expect(find.textContaining('Boîte de pizza : le bac brun.'), findsOneWidget);
    expect(find.text('Voir la fiche'), findsOneWidget);
  });

  testWidgets('signaler à la Ville : un message clair avec l’adresse', (tester) async {
    await pumpApp(tester, place: 'racine');
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Signaler un problème à la Ville'), 300);
    await tester.tap(find.text('Signaler un problème à la Ville'));
    await settle(tester);
    expect(find.byType(ReportScreen), findsOneWidget);
    await tester.tap(find.text('Lampadaire'));
    await settle(tester);
    expect(find.textContaining('Un lampadaire ne fonctionne pas.'), findsOneWidget);
    expect(find.textContaining('Endroit : 201, rue Racine Est.'), findsOneWidget);
  });

  testWidgets('la fiche des routes : la 175, et les caméras proches', (tester) async {
    final report = RoadReport(
      takenAt: sundayEvening,
      segments: parseRoadConditions(
        jsonDecode(fixture('conditions_routieres.json')) as Map<String, Object?>,
      ),
      cameras: parseCameras(jsonDecode(fixture('cameras.json')) as Map<String, Object?>),
    );
    await pumpApp(tester, place: 'racine', roads: RoadStatus(report, SourceOrigin.live));
    await tester.scrollUntilVisible(find.text('Dégagées'), 300);
    await tester.ensureVisible(find.text('Dégagées'));
    await tester.pump();
    await tester.tap(find.text('Dégagées'));
    await settle(tester);
    expect(find.text('Caméras près de chez toi'), findsOneWidget);
    expect(find.textContaining('Étape →'), findsOneWidget);
  });

  group('assistant en ligne', () {
    testWidgets('les communiqués de la Ville, en mots simples', (tester) async {
      await pumpApp(
        tester,
        place: 'racine',
        extra: [remoteAssistantProvider.overrideWithValue(FakeRemote())],
      );
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await settle(tester);
      expect(find.textContaining('jamais ton adresse'), findsOneWidget);
      await tester.ensureVisible(find.text('Les derniers communiqués de la Ville'));
      await tester.tap(find.text('Les derniers communiqués de la Ville'));
      await settle(tester);
      expect(find.text('Ponceau partiellement affaissé rang St-Martin'), findsOneWidget);
      expect(find.textContaining('rang Saint-Martin est fermée'), findsOneWidget);
      // Sans résumé : le titre et le lien.
      expect(find.text('Bilan de la saison de pavage 2026'), findsOneWidget);
      expect(find.text('Lire le communiqué'), findsNWidgets(2));
    });

    testWidgets('ce que l’app ne sait pas part au serveur, sans l’adresse', (tester) async {
      final remote = FakeRemote();
      await pumpApp(
        tester,
        place: 'racine',
        extra: [remoteAssistantProvider.overrideWithValue(remote)],
      );
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Où faire réparer mon vélo ?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(find.text('Réponse de l’assistant en ligne.'), findsOneWidget);
      final (question, context) = remote.asked.single;
      expect(question, 'Où faire réparer mon vélo ?');
      expect(context['secteur'], 'Chicoutimi');
      expect(jsonEncode(context), isNot(contains('201')));
    });

    testWidgets('l’alerte météo en mots simples', (tester) async {
      final remote = FakeRemote();
      final storm = Demo.moments.firstWhere((m) => m.weather != null);
      await pumpApp(
        tester,
        place: 'racine',
        realNow: DateTime(2026, 11, 18, 23),
        weather: WeatherStatus(storm.weather, SourceOrigin.live),
        extra: [remoteAssistantProvider.overrideWithValue(remote)],
      );
      unawaited(showDetailSheet(tester.element(find.byType(TodayScreen)), SignalKind.weather));
      await settle(tester);
      await tester.ensureVisible(find.text('En mots simples'));
      await tester.tap(find.text('En mots simples'));
      await settle(tester);
      expect(find.textContaining('prévois du temps demain matin'), findsOneWidget);
      expect(remote.explained.single, contains(storm.weather!.alerts.first.name));
    });

    testWidgets('sans serveur, rien de tout ça ne s’affiche', (tester) async {
      await pumpApp(tester, place: 'racine');
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await settle(tester);
      expect(find.text('Les derniers communiqués de la Ville'), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    });
  });

  group('tâche de fond', () {
    http.Client sources() => MockClient((r) async {
      final path = r.url.path;
      String body;
      if (path.contains('avis_aqueduc')) {
        body = fixture('avis_aqueduc.json');
      } else if (path.contains('etat_circulation')) {
        body = fixture('travaux.json');
      } else if (path.contains('citypageweather')) {
        body = '{"properties": {"lastUpdated": "2026-11-18T22:00:00Z"}}';
      } else if (path.contains('weather-alerts')) {
        body = '{"features": []}';
      } else if (path.endsWith('version.json')) {
        body = '"20261118220000"';
      } else if (path.contains('bismarkers')) {
        body = '{"pannes": []}';
      } else {
        body = '[]';
      }
      return http.Response.bytes(utf8.encode(body), 200);
    });

    test('app fermée : alertes, widget et rappels, sans Riverpod', () async {
      SharedPreferences.setMockInitialValues({'place': 'saint-jean'});
      final notifications = FakeNotifications()..saguenayNow = DateTime(2026, 10, 25, 7, 10);
      final widget = FakeHomeScreenWidget();
      await BackgroundRefresh.run(
        client: sources(),
        notifications: notifications,
        widget: widget,
        now: DateTime(2026, 10, 25, 7, 10),
      );
      // L'avis 2026-378 est en cours dans la couche réelle de la Ville.
      expect(notifications.waterAlerts.single.notice.number, '2026-378');
      expect(notifications.scheduled.single, isNotEmpty);
      expect(widget.shown.single.place, 'Ch. Saint-Jean');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('aqueduc'), contains('2026-378'));
      expect(prefs.getStringList('alertes-signalees'), contains('2026-378:en-cours'));
    });

    test('sans réseau : le dernier relevé gardé fait l’affaire', () async {
      SharedPreferences.setMockInitialValues({
        'place': 'racine',
        'aqueduc': jsonEncode(
          WaterSnapshot(takenAt: DateTime(2026, 10, 25), notices: const []).toJson(),
        ),
      });
      final widget = FakeHomeScreenWidget();
      await BackgroundRefresh.run(
        client: MockClient((_) async => throw const SocketException('pas de réseau')),
        notifications: FakeNotifications()..saguenayNow = DateTime(2026, 10, 25, 9),
        widget: widget,
        now: DateTime(2026, 10, 25, 9),
      );
      expect(widget.shown, hasLength(1));
    });

    test('sans adresse : rien à faire', () async {
      SharedPreferences.setMockInitialValues({});
      final widget = FakeHomeScreenWidget();
      await BackgroundRefresh.run(
        client: sources(),
        notifications: FakeNotifications(),
        widget: widget,
      );
      expect(widget.shown, isEmpty);
    });
  });
}
