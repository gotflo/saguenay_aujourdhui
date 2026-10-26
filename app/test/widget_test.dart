import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/state/live_sources.dart';
import 'package:saguenay_aujourdhui/state/providers.dart';
import 'package:saguenay_aujourdhui/theme/colors.dart';
import 'package:saguenay_core/saguenay_core.dart';

import 'helpers.dart';

void main() {
  testWidgets('sans adresse, on la choisit, et la permission est demandée à ce moment', (
    tester,
  ) async {
    final notifications = await pumpApp(tester);
    expect(find.text('Choisis ton adresse'), findsOneWidget);
    expect(notifications.permissionRequests, 0);

    await tester.ensureVisible(find.text('201, rue Racine Est'));
    await tester.pump();
    await tester.tap(find.text('201, rue Racine Est'));
    await settle(tester);
    expect(find.text('Bonsoir'), findsOneWidget);
    expect(notifications.permissionRequests, 1);
    // Laisse finir les minuteries lancées par la transition vers l'écran du jour.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('un dimanche soir de novembre, le stationnement passe en premier', (tester) async {
    await pumpApp(tester, place: 'racine');
    expect(find.text('Pas d’auto dans la rue cette nuit'), findsOneWidget);
    expect(find.text('Aussi aujourd’hui'), findsOneWidget);

    await tester.tap(find.text('Pourquoi je vois ça ?'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Plus minuit approche'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Plus minuit approche'), findsNothing);
  });

  testWidgets('une tuile ouvre ses détails', (tester) async {
    await pumpApp(tester, place: 'racine');
    await tester.tap(find.text('Ordures'));
    await settle(tester);
    expect(find.text('Collectes'), findsOneWidget);
    expect(find.text('Le bac va au chemin la veille et se rentre avant midi.'), findsOneWidget);
  });

  testWidgets('avis d’ébullition : la carte du haut passe au rouge', (tester) async {
    await pumpApp(tester, place: 'saint-jean', at: DateTime(2026, 10, 25, 7, 10));
    expect(find.text('Fais bouillir l’eau avant de la boire'), findsOneWidget);
    expect(find.text('Bonjour'), findsOneWidget);
    final card = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Fais bouillir l’eau avant de la boire'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((card.decoration! as BoxDecoration).color, AppColors.light.critical);
  });

  testWidgets('les urgences en direct affichent l’heure du relevé', (tester) async {
    final snapshot = EmergencySnapshot(
      takenAt: DateTime(2026, 11, 15, 20, 45),
      rooms: Demo.emergencies.rooms,
    );
    await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 15, 21, 30),
      emergencies: EmergencyStatus(snapshot, SourceOrigin.live),
    );
    await tester.scrollUntilVisible(find.text('Voir l’achalandage').hitTestable(), 200);
    await tester.tap(find.text('Voir l’achalandage'));
    await settle(tester);
    expect(find.text('En direct du ministère, relevé de 20 h 45'), findsOneWidget);
    expect(find.text('Hôpital de Chicoutimi'), findsOneWidget);
  });

  testWidgets('un relevé vieux de plus de trois heures est signalé', (tester) async {
    final snapshot = EmergencySnapshot(
      takenAt: DateTime(2026, 11, 15, 12, 45),
      rooms: Demo.emergencies.rooms,
    );
    await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 15, 21, 30),
      emergencies: EmergencyStatus(snapshot, SourceOrigin.live),
    );
    await tester.scrollUntilVisible(find.text('Voir l’achalandage').hitTestable(), 200);
    await tester.tap(find.text('Voir l’achalandage'));
    await settle(tester);
    expect(find.textContaining('Le ministère n’a rien publié depuis'), findsOneWidget);
  });

  testWidgets('le thème de la Ville remplace le jaune par le bleu', (tester) async {
    await pumpApp(tester, place: 'racine');
    containerOf(tester).read(paletteProvider.notifier).choose(AppPalette.ville);
    await settle(tester);
    final card = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Pas d’auto dans la rue cette nuit'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((card.decoration! as BoxDecoration).color, AppColors.villeLight.accent);
  });

  testWidgets('les réglages gardent les choix et envoient un rappel test', (tester) async {
    final notifications = await pumpApp(tester, place: 'racine');
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    expect(find.text('Réglages'), findsOneWidget);

    final roadwork = find.descendant(
      of: find.ancestor(of: find.text('Travaux sur ma rue'), matching: find.byType(MergeSemantics)),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(roadwork);
    await tester.pump();
    await tester.tap(roadwork);
    await settle(tester);
    expect(containerOf(tester).read(remindersProvider), contains(ReminderKind.roadwork));
    expect(notifications.permissionRequests, 1);

    await tester.tap(find.text('M’envoyer un rappel test'));
    await settle(tester);
    expect(notifications.tests, 1);
  });

  testWidgets('si les notifications sont bloquées, on le dit', (tester) async {
    final blocked = FakeNotifications()..allow = false;
    await pumpApp(tester, place: 'racine', notifications: blocked);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    await tester.tap(find.text('M’envoyer un rappel test'));
    await settle(tester);
    expect(blocked.tests, 0);
    expect(find.textContaining('bloquées'), findsOneWidget);
  });

  testWidgets('oublier son adresse ramène à l’accueil', (tester) async {
    await pumpApp(tester, place: 'racine');
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Oublier mon adresse'), 300);
    await tester.tap(find.text('Oublier mon adresse'));
    await settle(tester);
    expect(find.text('Choisis ton adresse'), findsOneWidget);
  });

  testWidgets('rejouer un moment montre son adresse sans changer la mienne', (tester) async {
    await pumpApp(tester, place: 'racine');
    await tester.tap(find.text('Démo'));
    await settle(tester);
    await tester.tap(find.text('Avis d’ébullition, ce matin'));
    await settle(tester);
    final container = containerOf(tester);
    expect(container.read(placeIdProvider), 'racine');
    expect(container.read(placeProvider)?.id, 'saint-jean');
    expect(container.read(demoTimeProvider), DateTime(2026, 10, 25, 7, 10));
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(find.text('Fais bouillir l’eau avant de la boire'), findsOneWidget);

    container.read(demoMomentProvider.notifier).stop();
    await settle(tester);
    expect(container.read(placeProvider)?.id, 'racine');
  });

  testWidgets('une mise en situation de tempête passe la météo en premier', (tester) async {
    await pumpApp(tester, place: 'racine');
    final storm = Demo.moments.firstWhere((m) => m.weather != null);
    containerOf(tester).read(demoMomentProvider.notifier).play(storm);
    await settle(tester);
    expect(find.text('Avertissement de neige'), findsOneWidget);
    expect(find.text('Accumulation de 15 à 20 cm.'), findsOneWidget);
  });

  testWidgets('toucher la carte du haut ouvre sa fiche', (tester) async {
    await pumpApp(tester, place: 'racine');
    await tester.tap(find.text('Pas d’auto dans la rue cette nuit'));
    await settle(tester);
    expect(find.text('Règlement de la Ville'), findsOneWidget);
  });

  testWidgets('la semaine à venir, sous les tuiles', (tester) async {
    await pumpApp(tester, place: 'racine', at: DateTime(2026, 10, 25, 9));
    await tester.scrollUntilVisible(find.text('Ta semaine'), 300);
    await tester.scrollUntilVisible(find.text('Mardi 27 oct.'), 300);
    expect(find.text('Recyclage'), findsWidgets);
    expect(find.text('Travaux sur ta rue jusqu’au 6 nov.'), findsOneWidget);
  });

  testWidgets('les sources, et ce qui marche sans réseau', (tester) async {
    await pumpApp(tester, place: 'racine');
    await tester.scrollUntilVisible(find.text('D’où viennent ces infos ?'), 300);
    await tester.tap(find.text('D’où viennent ces infos ?'));
    await settle(tester);
    expect(find.text('Neuf sources, une seule app'), findsOneWidget);
    expect(find.textContaining('calculé sur le téléphone'), findsWidgets);
  });

  testWidgets('hors ligne : une petite pastille, et l’app continue', (tester) async {
    final weather = WeatherSnapshot(takenAt: DateTime(2026, 11, 15, 20), temperature: -2);
    await pumpApp(
      tester,
      place: 'racine',
      weather: WeatherStatus(weather, SourceOrigin.cached),
      realNow: DateTime(2026, 11, 15, 21, 30),
    );
    // La pastille ne s'affiche pas en démo : on revient à l'heure réelle.
    containerOf(tester).read(demoTimeProvider.notifier).set(null);
    await settle(tester);
    expect(find.text('Hors ligne'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('une adresse inconnue ramène à l’accueil plutôt qu’à un écran vide', (tester) async {
    await pumpApp(tester, place: 'adresse-retiree');
    expect(find.text('Choisis ton adresse'), findsOneWidget);
  });
}
