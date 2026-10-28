import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/home_widget/widget_sync.dart';
import 'package:saguenay_aujourdhui/state/launch.dart';
import 'package:saguenay_aujourdhui/state/live_sources.dart';
import 'package:saguenay_aujourdhui/state/providers.dart';
import 'package:saguenay_core/saguenay_core.dart';

import 'helpers.dart';

void main() {
  final now = DateTime(2026, 11, 18, 7, 35);

  testWidgets('le widget reçoit sept jours, une entrée par changement', (tester) async {
    final widget = FakeHomeScreenWidget();
    await pumpApp(tester, place: 'racine', realNow: now, homeScreen: widget);
    final content = widget.shown.last;

    expect(content.place, 'Racine Est');
    expect(content.until, now.add(const Duration(days: 7)));
    final entries = (jsonDecode(content.timeline) as List).cast<Map<String, Object?>>();
    expect(entries.first['at'], now.millisecondsSinceEpoch);
    expect(entries.first['title'], 'Le 105 passe à 7 h 46');
    expect(content.changes, hasLength(entries.length - 1));
    for (var i = 1; i < content.changes.length; i++) {
      expect(content.changes[i].isAfter(content.changes[i - 1]), isTrue);
    }
    for (final e in entries) {
      expect('${e['title']} ${e['body']}', isNot(matches(RegExp(r'dans \d'))));
    }
  });

  testWidgets('la démo ne touche pas au widget', (tester) async {
    final widget = FakeHomeScreenWidget();
    await pumpApp(tester, place: 'racine', realNow: now, homeScreen: widget);
    final count = widget.shown.length;
    containerOf(tester).read(demoMomentProvider.notifier).play(Demo.moments[1]);
    await settle(tester);
    expect(widget.shown.length, count);
    expect(widget.shown.last.place, 'Racine Est');
  });

  testWidgets('une panne en direct entre dans le widget', (tester) async {
    final widget = FakeHomeScreenWidget();
    final power = PowerSnapshot(
      takenAt: now,
      outages: [
        PowerOutage(
          customers: 300,
          start: now.subtract(const Duration(minutes: 20)),
          end: now.add(const Duration(hours: 2)),
          lat: 48.4290,
          lon: -71.0630,
        ),
      ],
    );
    await pumpApp(
      tester,
      place: 'racine',
      realNow: now,
      homeScreen: widget,
      power: PowerStatus(power, SourceOrigin.live),
    );
    final entries = (jsonDecode(widget.shown.last.timeline) as List).cast<Map<String, Object?>>();
    expect(entries.first['title'], 'Panne dans ton secteur');
    expect(entries.first['kind'], 'power');
  });

  testWidgets('sans adresse, le widget est vidé', (tester) async {
    final widget = FakeHomeScreenWidget();
    await pumpApp(tester, place: 'racine', realNow: now, homeScreen: widget);
    await containerOf(tester).read(placeIdProvider.notifier).forget();
    await settle(tester);
    expect(widget.cleared, greaterThanOrEqualTo(1));
  });

  testWidgets('un toucher sur le widget ouvre la fiche affichée', (tester) async {
    final widget = FakeHomeScreenWidget();
    await pumpApp(tester, place: 'racine', homeScreen: widget);
    widget.click(Uri.parse('aujourdhui://detail/collection'));
    await settle(tester);
    expect(find.text('Le bac va au chemin la veille et se rentre avant midi.'), findsOneWidget);
  });

  testWidgets('l’app lancée depuis un raccourci ouvre la fiche', (tester) async {
    final widget = FakeHomeScreenWidget()
      ..launchedWith = Uri.parse('aujourdhui://detail/emergency');
    await pumpApp(tester, place: 'racine', homeScreen: widget);
    await settle(tester);
    expect(find.text('Hôpital de Chicoutimi'), findsOneWidget);
  });

  test('les adresses de lancement inconnues sont ignorées', () {
    expect(kindFromLaunch('detail:water'), SignalKind.water);
    expect(kindFromLaunch('aujourdhui://detail/power?homeWidget'), SignalKind.power);
    expect(kindFromLaunch('aujourdhui://detail/../../etc'), isNull);
    expect(kindFromLaunch('https://exemple.test/detail/water'), isNull);
    expect(kindFromLaunch('detail:inconnu'), isNull);
    expect(kindFromLaunch(null), isNull);
  });

  test('le calcul du widget tient dans un isolat : rien d’impossible à copier', () async {
    final place = Demo.place('racine');
    final city = Demo.city;
    final at = DateTime(2026, 11, 18, 7, 35);
    final content = await Isolate.run(() => WidgetContent.compute(place, city, at));
    expect(content.timeline, isNotEmpty);
  });
}
