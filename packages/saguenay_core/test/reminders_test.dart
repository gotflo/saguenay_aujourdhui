import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

void main() {
  const planner = ReminderPlanner();
  final racine = Demo.place('racine');
  const all = {ReminderKind.parking, ReminderKind.collection, ReminderKind.roadwork};

  test('le 14 novembre au soir : première nuit, puis un rappel chaque soir', () {
    final plan = planner.plan(racine, DateTime(2026, 11, 14, 8), enabled: {ReminderKind.parking});
    expect(plan.first.at, DateTime(2026, 11, 14, 21));
    expect(plan.first.title, 'Première nuit sans auto dans la rue');
    expect(plan[1].at, DateTime(2026, 11, 15, 21));
    expect(plan[1].title, 'Pas d’auto dans la rue cette nuit');
    expect(plan.where((r) => r.kind == ReminderKind.parking), hasLength(28));
  });

  test('le bac la veille à 19 h', () {
    final plan = planner.plan(
      racine,
      DateTime(2026, 10, 25, 8),
      enabled: {ReminderKind.collection},
    );
    expect(plan.first.at, DateTime(2026, 10, 26, 19));
    expect(plan.first.title, 'Sors le bac bleu');
  });

  test('les travaux sur ma rue, les matins de semaine seulement', () {
    final plan = planner.plan(racine, DateTime(2026, 10, 25, 8), enabled: {ReminderKind.roadwork});
    expect(plan.first.at, DateTime(2026, 10, 26, 6, 45));
    expect(plan.first.body, 'Boul. du Saguenay Est, à contresens.');
    expect(plan.every((r) => r.at.weekday <= DateTime.friday), isTrue);
  });

  test('rien de passé, rien de désactivé, et jamais plus de 60', () {
    final from = DateTime(2026, 11, 20, 20);
    final plan = planner.plan(racine, from, enabled: all, days: 60);
    expect(plan.every((r) => r.at.isAfter(from)), isTrue);
    expect(plan.length, lessThanOrEqualTo(ReminderPlanner.maxPending));
    expect(planner.plan(racine, from, enabled: const {}), isEmpty);
  });

  test('deux jours avant la fin, un rappel invite à rouvrir l’app', () {
    final from = DateTime(2026, 11, 14, 8);
    final plan = planner.plan(racine, from, enabled: {ReminderKind.parking});
    final renew = plan.singleWhere((r) => r.id == ReminderPlanner.renewId);
    expect(renew.kind, isNull);
    expect(renew.at, DateTime(2026, 12, 10, 12));
    expect(planner.plan(racine, from, enabled: const {}), isEmpty);
  });

  test('le résumé du dimanche, à 18 h', () {
    final plan = planner.plan(
      racine,
      DateTime(2026, 10, 25, 8),
      enabled: {ReminderKind.week},
      city: Demo.city,
    );
    final sunday = plan.first;
    expect(sunday.at, DateTime(2026, 10, 25, 18));
    expect(sunday.title, 'Ta semaine');
    expect(sunday.body, 'Recyclage mardi. Travaux sur ta rue jusqu’au 6 nov.');
  });

  test('une coupure de courant planifiée, la veille au soir', () {
    final moment = Demo.moments.firstWhere((m) => m.power != null);
    final plan = planner.plan(
      racine,
      DateTime(2026, 10, 29, 8),
      enabled: {ReminderKind.power},
      city: CityData(power: moment.power),
    );
    expect(plan.first.at, DateTime(2026, 10, 29, 19));
    expect(plan.first.title, 'Demain, courant coupé de 9 h à 13 h');
  });

  test('les identifiants ne se répètent pas et restent sous ceux des alertes', () {
    final plan = planner.plan(
      racine,
      DateTime(2026, 11, 14),
      enabled: ReminderKind.values.toSet(),
      city: Demo.city,
    );
    expect(plan.map((r) => r.id).toSet(), hasLength(plan.length));
    expect(plan.length, lessThanOrEqualTo(ReminderPlanner.maxPending));
    expect(plan.where((r) => r.id != ReminderPlanner.renewId).every((r) => r.id < 800000), isTrue);
  });

  group('alertes météo', () {
    final storm = Demo.moments.firstWhere((m) => m.weather != null);
    final city = CityData(weather: storm.weather);

    test('un avertissement se signale une seule fois', () {
      final first = WeatherAlerts.due(city, storm.at);
      expect(first.single.title, 'Avertissement de neige');
      expect(first.single.id, inInclusiveRange(800000, 899998));
      expect(WeatherAlerts.due(city, storm.at, alreadySent: {first.single.key}), isEmpty);
    });

    test('un simple bulletin reste dans l’app, sans notification', () {
      final calm = CityData(
        weather: WeatherSnapshot(
          takenAt: storm.at,
          alerts: [
            WeatherAlert(
              name: 'Bulletin météorologique spécial',
              level: WeatherAlertLevel.statement,
              issuedAt: storm.at,
            ),
          ],
        ),
      );
      expect(WeatherAlerts.due(calm, storm.at), isEmpty);
    });

    test('une alerte terminée ne se signale pas', () {
      expect(WeatherAlerts.due(city, DateTime(2026, 11, 19, 13)), isEmpty);
    });
  });

  group('avis d’eau', () {
    final saintJean = Demo.place('saint-jean');

    test('un avis d’ébullition en cours se signale une seule fois', () {
      final now = DateTime(2026, 10, 25, 7, 10);
      final first = WaterAlerts.due(saintJean, Demo.city, now);
      expect(first.single.title, 'Avis d’ébullition à ton adresse');
      final again = WaterAlerts.due(saintJean, Demo.city, now, alreadySent: {first.single.key});
      expect(again, isEmpty);
    });

    test('une coupure annoncée pour demain', () {
      final place = Place(
        id: 'test',
        label: '1re Avenue',
        shortLabel: '1re Avenue',
        collection: const CollectionSchedule({}),
        waterNotices: const ['2026-376'],
      );
      final alerts = WaterAlerts.due(place, Demo.city, DateTime(2026, 10, 25, 18));
      expect(alerts.single.title, 'Demain, coupure d’eau de 8 h à 15 h');
      expect(alerts.single.upcoming, isTrue);
    });

    test('rien quand l’adresse n’est pas touchée', () {
      expect(WaterAlerts.due(racine, Demo.city, DateTime(2026, 10, 25, 7)), isEmpty);
    });
  });

  test('un relevé des urgences survit à un aller-retour en JSON', () {
    final copy = EmergencySnapshot.fromJson(Demo.emergencies.toJson());
    expect(copy.takenAt, Demo.emergencies.takenAt);
    expect(copy.rooms.first.occupancyPercent, 83);
    expect(copy.isStaleAt(DateTime(2026, 10, 25, 11)), isTrue);
  });

  group('heures calmes', () {
    final storm = Demo.moments.firstWhere((m) => m.weather != null);
    final weatherAlert = WeatherAlerts.due(CityData(weather: storm.weather), storm.at).single;

    test('une alerte météo de 23 h attend 7 h le lendemain', () {
      expect(
        QuietHours.deferral(weatherAlert, DateTime(2026, 11, 18, 23)),
        DateTime(2026, 11, 19, 7),
      );
      expect(
        QuietHours.deferral(weatherAlert, DateTime(2026, 11, 19, 3)),
        DateTime(2026, 11, 19, 7),
      );
      expect(QuietHours.deferral(weatherAlert, DateTime(2026, 11, 19, 9)), isNull);
    });

    test('un avis d’ébullition passe même la nuit', () {
      final boil = WaterAlerts.due(
        Demo.place('saint-jean'),
        Demo.city,
        DateTime(2026, 10, 25, 7),
      ).single;
      expect(QuietHours.deferral(boil, DateTime(2026, 10, 25, 2)), isNull);
    });
  });
}
