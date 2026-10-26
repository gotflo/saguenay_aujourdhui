import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/notifications/notification_sync.dart';
import 'package:saguenay_aujourdhui/notifications/notifications.dart';
import 'package:saguenay_aujourdhui/state/live_sources.dart';
import 'package:saguenay_aujourdhui/state/providers.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// Des notifications lentes, comme sur un vrai téléphone : chaque appel prend du temps.
class SlowNotifications extends FakeNotifications {
  int running = 0;
  int maxRunning = 0;

  @override
  Future<void> replaceScheduled(List<PlannedReminder> reminders) async {
    running++;
    if (running > maxRunning) maxRunning = running;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    scheduled.add(reminders);
    running--;
  }
}

void main() {
  testWidgets('les rappels des prochaines semaines sont programmés pour l’adresse', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 14, 8),
    );
    final plan = notifications.scheduled.last;
    expect(
      plan.where((r) => r.at == DateTime(2026, 11, 14, 21)).single.title,
      'Première nuit sans auto dans la rue',
    );
    expect(
      plan.where((r) => r.at == DateTime(2026, 11, 15, 19)).single.title,
      'Sors le bac à ordures',
    );
    expect(plan.where((r) => r.kind == ReminderKind.roadwork), isEmpty);
    expect(plan.where((r) => r.kind == ReminderKind.week), isNotEmpty);
    expect(plan.last.at.isAfter(DateTime(2026, 12, 1)), isTrue);
  });

  testWidgets('couper un type de rappel le retire de la programmation', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 14, 8),
    );
    await containerOf(tester).read(remindersProvider.notifier).toggle(ReminderKind.parking, false);
    await settle(tester);
    expect(notifications.scheduled.last.where((r) => r.kind == ReminderKind.parking), isEmpty);
    expect(notifications.scheduled.last, isNotEmpty);
  });

  testWidgets('deux changements rapprochés ne se mélangent pas', (tester) async {
    final notifications = SlowNotifications();
    await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 14, 8),
      notifications: notifications,
    );
    final reminders = containerOf(tester).read(remindersProvider.notifier);
    await reminders.toggle(ReminderKind.parking, false);
    await tester.pump(const Duration(milliseconds: 50));
    await reminders.toggle(ReminderKind.collection, false);
    await tester.pump(const Duration(milliseconds: 50));
    await reminders.toggle(ReminderKind.week, false);
    await tester.pump(const Duration(seconds: 2));

    expect(notifications.maxRunning, 1);
    final last = notifications.scheduled.last;
    expect(
      last.where(
        (r) => {ReminderKind.parking, ReminderKind.collection, ReminderKind.week}.contains(r.kind),
      ),
      isEmpty,
    );
  });

  testWidgets('rien ne change : on ne reprogramme pas pour rien', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 14, 8),
    );
    final before = notifications.scheduled.length;
    containerOf(tester).invalidate(reminderSyncProvider);
    await settle(tester);
    expect(notifications.scheduled.length, before);
  });

  testWidgets('changer d’adresse reprogramme', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 14, 8),
    );
    final before = notifications.scheduled.length;
    await containerOf(tester).read(placeIdProvider.notifier).choose('saint-pierre');
    await settle(tester);
    expect(notifications.scheduled.length, greaterThan(before));
  });

  testWidgets('oublier son adresse annule tous les rappels', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 14, 8),
    );
    expect(notifications.scheduled.last, isNotEmpty);
    await containerOf(tester).read(placeIdProvider.notifier).forget();
    await settle(tester);
    expect(notifications.scheduled.last, isEmpty);
  });

  testWidgets('une démo ne touche pas aux vrais rappels', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 14, 8),
    );
    final before = notifications.scheduled.length;
    containerOf(tester).read(demoMomentProvider.notifier).play(Demo.moments[1]);
    await settle(tester);
    expect(notifications.scheduled.length, before);
    expect(containerOf(tester).read(placeIdProvider), 'racine');
    expect(notifications.waterAlerts, isEmpty);
  });

  testWidgets('les rappels suivent l’heure de Saguenay, pas celle du téléphone', (tester) async {
    // Téléphone réglé sur Vancouver : il est 19 h là-bas, 22 h à Saguenay.
    final notifications = FakeNotifications()..saguenayNow = DateTime(2026, 11, 20, 22);
    await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 11, 20, 19),
      notifications: notifications,
    );
    final first = notifications.scheduled.last.first;
    expect(first.at.isAfter(DateTime(2026, 11, 20, 22)), isTrue);
  });

  testWidgets('un avis d’ébullition est signalé une seule fois', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'saint-jean',
      realNow: DateTime(2026, 10, 25, 7, 10),
    );
    expect(notifications.waterAlerts.single.title, 'Avis d’ébullition à ton adresse');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('alertes-signalees'), contains('2026-378:en-cours'));

    containerOf(tester).invalidate(liveCityProvider);
    await settle(tester);
    expect(notifications.waterAlerts, hasLength(1));
  });

  testWidgets('un avis déjà signalé par une version précédente ne revient pas', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'saint-jean',
      realNow: DateTime(2026, 10, 25, 7, 10),
      prefs: {
        'avis-signales': ['2026-378:en-cours'],
      },
    );
    expect(notifications.waterAlerts, isEmpty);
  });

  testWidgets('sans permission, l’avis attend et part dès qu’elle est donnée', (tester) async {
    final notifications = FakeNotifications()..allow = false;
    await pumpApp(
      tester,
      place: 'saint-jean',
      realNow: DateTime(2026, 10, 25, 7, 10),
      notifications: notifications,
    );
    expect(notifications.waterAlerts, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('alertes-signalees'), isNull);

    notifications.allow = true;
    containerOf(tester).invalidate(alertSyncProvider);
    await settle(tester);
    expect(notifications.waterAlerts.single.title, 'Avis d’ébullition à ton adresse');
  });

  testWidgets('choisir l’adresse puis accepter : l’avis arrive', (tester) async {
    final notifications = FakeNotifications();
    await pumpApp(tester, realNow: DateTime(2026, 10, 25, 7, 10), notifications: notifications);
    await tester.ensureVisible(find.text('3100, chemin Saint-Jean'));
    await tester.pump();
    await tester.tap(find.text('3100, chemin Saint-Jean'));
    await settle(tester);
    expect(notifications.permissionRequests, 1);
    expect(notifications.waterAlerts, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('pas d’avis d’eau si ce rappel est coupé', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'saint-jean',
      realNow: DateTime(2026, 10, 25, 7, 10),
      prefs: {
        'reminders': ['parking', 'collection'],
      },
    );
    expect(notifications.waterAlerts, isEmpty);
  });

  testWidgets('pas d’avis d’eau pour une adresse qui n’est pas touchée', (tester) async {
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: DateTime(2026, 10, 25, 7, 10),
    );
    expect(notifications.waterAlerts, isEmpty);
  });

  testWidgets('un avertissement météo en direct est signalé une fois', (tester) async {
    final storm = Demo.moments.firstWhere((m) => m.weather != null);
    final notifications = await pumpApp(
      tester,
      place: 'racine',
      realNow: storm.at,
      weather: WeatherStatus(storm.weather, SourceOrigin.live),
    );
    expect(notifications.alerts.single.title, 'Avertissement de neige');
    expect(notifications.alerts.single.kind, ReminderKind.weather);
    expect(payloadFor(notifications.alerts.single.kind), 'detail:weather');
  });

  testWidgets('toucher une notification ouvre la bonne fiche', (tester) async {
    final notifications = await pumpApp(tester, place: 'racine');
    notifications.tap('detail:collection');
    await settle(tester);
    expect(find.text('Le bac va au chemin la veille et se rentre avant midi.'), findsOneWidget);
  });

  testWidgets('l’app lancée par une notification ouvre la fiche tout de suite', (tester) async {
    final notifications = FakeNotifications()..launchedWith = 'detail:parking';
    await pumpApp(tester, place: 'racine', notifications: notifications);
    await settle(tester);
    expect(find.text('Stationnement de nuit'), findsOneWidget);
    expect(find.text('Règlement de la Ville'), findsOneWidget);
  });

  testWidgets('notifications bloquées : un raccourci vers les réglages du téléphone', (
    tester,
  ) async {
    final notifications = FakeNotifications()..allow = false;
    await pumpApp(tester, place: 'racine', notifications: notifications);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    await tester.tap(find.text('Les notifications sont bloquées'));
    await settle(tester);
    expect(notifications.settingsOpened, 1);
  });

  testWidgets('sans alarmes exactes, l’app propose de les autoriser', (tester) async {
    final notifications = FakeNotifications()..exact = false;
    await pumpApp(tester, place: 'racine', notifications: notifications);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settle(tester);
    await tester.tap(find.text('Rappels à l’heure pile'));
    await settle(tester);
    expect(notifications.exactRequests, 1);
  });
}
