import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/notifications/notifications.dart';
import 'package:saguenay_aujourdhui/state/launch.dart';
import 'package:saguenay_aujourdhui/state/live_sources.dart';
import 'package:saguenay_aujourdhui/widgets/live_map.dart';
import 'package:saguenay_aujourdhui/widgets/weather_fall.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'live_address_test.dart' show liveAddress, racineAddress;

const maman = ResolvedAddress(
  civic: '2687',
  street: 'Boulevard du Royaume',
  sector: 'Jonquière',
  lat: 48.4051,
  lon: -71.1738,
);

Map<String, Object> addresses({bool withMaman = false}) => {
  'adresses': [
    jsonEncode(racineAddress.toJson()),
    if (withMaman) jsonEncode(maman.named('Chez maman').toJson()),
  ],
  'place': racineAddress.id,
};

void main() {
  testWidgets('une panne chez un proche : signalée sous son nom', (tester) async {
    final power = PowerSnapshot(
      takenAt: sundayEvening,
      outages: [
        PowerOutage(
          customers: 120,
          start: sundayEvening.subtract(const Duration(hours: 1)),
          lat: 48.405,
          lon: -71.174,
        ),
      ],
    );
    final n = await pumpApp(
      tester,
      prefs: addresses(withMaman: true),
      power: PowerStatus(power, SourceOrigin.live),
      extra: liveAddress(),
    );
    expect(n.alerts.map((a) => a.title), contains('Chez maman : panne de courant'));
  });

  testWidgets('une adresse reçue par lien : on la nomme, elle est suivie, rien d’autre ne change', (
    tester,
  ) async {
    final links = StreamController<Uri>();
    addTearDown(links.close);
    await pumpApp(
      tester,
      prefs: addresses(),
      extra: [...liveAddress(), appLinksProvider.overrideWithValue(links.stream)],
    );
    links.add(AddressLink.encode(maman));
    await settle(tester);
    expect(find.text('Une adresse partagée'), findsOneWidget);
    // La feuille s'ouvre après l'image qui a reçu le lien.
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.text('Chez mes parents'));
    await tester.tap(find.text('Chez mes parents'));
    await tester.pump();
    await tester.ensureVisible(find.text('Ajouter'));
    await tester.tap(find.text('Ajouter'));
    await settle(tester);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('adresses')!;
    expect(saved, hasLength(2));
    expect(saved.last, contains('Chez mes parents'));
    expect(prefs.getString('place'), racineAddress.id);
  });

  testWidgets('un lien hors de Saguenay est ignoré', (tester) async {
    final links = StreamController<Uri>();
    addTearDown(links.close);
    await pumpApp(
      tester,
      prefs: addresses(),
      extra: [...liveAddress(), appLinksProvider.overrideWithValue(links.stream)],
    );
    links.add(
      Uri.parse(
        'aujourdhui://adresse?c=1&r=Rue%20Sainte-Catherine&s=Montr%C3%A9al&la=45.5&lo=-73.5',
      ),
    );
    await settle(tester);
    expect(find.text('Une adresse partagée'), findsNothing);
  });

  testWidgets('la fiche de l’eau montre la zone de l’avis sur une carte', (tester) async {
    final boil = WaterNotice(
      number: '2026-400',
      type: WaterNoticeType.boil,
      start: sundayEvening.subtract(const Duration(days: 1)),
      zone: 'Centre-ville de Chicoutimi',
      rings: const [
        [(-71.07, 48.42), (-71.05, 48.42), (-71.05, 48.44), (-71.07, 48.44), (-71.07, 48.42)],
      ],
    );
    final n = await pumpApp(
      tester,
      prefs: addresses(),
      water: WaterStatus(WaterSnapshot(takenAt: sundayEvening, notices: [boil]), SourceOrigin.live),
      extra: liveAddress(),
    );
    n.tap('detail:water');
    await settle(tester);
    expect(find.byType(LiveMap), findsOneWidget);
  });

  testWidgets('une pointe d’Hydro-Québec dans la fiche de l’électricité', (tester) async {
    final tomorrow = DateTime(2026, 11, 16);
    final peaks = PeakSnapshot(
      takenAt: sundayEvening,
      events: [
        PeakEvent(
          start: tomorrow.add(const Duration(hours: 6)),
          end: tomorrow.add(const Duration(hours: 10)),
          offers: const {'CPC-D', 'TPC-DPC'},
        ),
      ],
    );
    final n = await pumpApp(
      tester,
      prefs: addresses(),
      peaks: PeakStatus(peaks, SourceOrigin.live),
      extra: liveAddress(),
    );
    n.tap(payloadFor(ReminderKind.peak)!);
    await settle(tester);
    expect(find.text('Pointe de consommation'), findsOneWidget);
    expect(find.textContaining('de 6 h à 10 h'), findsWidgets);
  });

  test('la pointe ouvre la fiche de l’électricité', () {
    expect(payloadFor(ReminderKind.peak), 'detail:power');
  });

  test('ce qui tombe, d’après la météo relevée', () {
    expect(fallingFrom('Neige légère'), Falling.snow);
    expect(fallingFrom('Pluie et neige'), Falling.snow);
    expect(fallingFrom('Pluie faible'), Falling.rain);
    expect(fallingFrom('Averses'), Falling.rain);
    expect(fallingFrom('Nuageux'), isNull);
    expect(fallingFrom('Possibilité d’averses'), isNull);
    expect(fallingFrom("possibilité d'averses"), isNull);
    expect(fallingFrom('Risque de neige'), isNull);
    expect(fallingFrom(null), isNull);
  });

  testWidgets('moins d’animations demandées : rien ne tombe', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: WeatherFall(falling: Falling.snow, color: Colors.black),
      ),
    );
    expect(find.byType(CustomPaint), findsNothing);
  });
}
