import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

void main() {
  const agenda = Agenda();
  final racine = Demo.place('racine');

  test('la semaine du 25 octobre au 201, rue Racine Est', () {
    final week = agenda.week(racine, Demo.city, DateTime(2026, 10, 25, 9));
    expect(week.days.first.day, DateTime(2026, 10, 27));
    expect(week.days.first.items.single.title, 'Recyclage');
    expect(week.ongoing.single.title, 'Travaux sur ta rue jusqu’au 6 nov.');
    expect(week.summary(), 'Recyclage mardi. Travaux sur ta rue jusqu’au 6 nov.');
  });

  test('la première nuit d’hiver apparaît la veille du 15 novembre', () {
    final week = agenda.week(racine, Demo.city, DateTime(2026, 11, 10));
    final day = week.days.firstWhere((d) => d.items.any((i) => i.kind == SignalKind.parking));
    expect(day.day, DateTime(2026, 11, 14));
    expect(week.ongoing.where((i) => i.kind == SignalKind.parking), isEmpty);
  });

  test('en plein hiver, une seule ligne pour toutes les nuits', () {
    final week = agenda.week(racine, Demo.city, DateTime(2026, 12, 7));
    expect(week.ongoing.first.title, 'Chaque nuit, pas d’auto dans la rue');
    expect(week.days.expand((d) => d.items).where((i) => i.kind == SignalKind.parking), isEmpty);
  });

  test('une coupure d’eau annoncée et un avis d’ébullition en cours', () {
    final place = Place(
      id: 'test',
      label: 'Test',
      shortLabel: 'Test',
      collection: const CollectionSchedule({}),
      waterNotices: const ['2026-376', '2026-378'],
    );
    final week = agenda.week(place, Demo.city, DateTime(2026, 10, 25, 9));
    expect(week.ongoing.single.title, 'Avis d’ébullition en cours');
    expect(week.days.single.items.single.detail, 'de 8 h à 15 h');
  });

  test('une coupure de courant planifiée dans le secteur', () {
    final moment = Demo.moments.firstWhere((m) => m.power != null);
    final week = agenda.week(racine, CityData(power: moment.power), DateTime(2026, 10, 29, 8));
    final day = week.days.firstWhere((d) => d.items.any((i) => i.kind == SignalKind.power));
    expect(day.day, DateTime(2026, 10, 30));
  });

  test('rien de prévu : pas de résumé', () {
    const place = Place(
      id: 'vide',
      label: 'Vide',
      shortLabel: 'Vide',
      collection: CollectionSchedule({}),
    );
    final week = agenda.week(place, const CityData(), DateTime(2026, 10, 25));
    expect(week.isEmpty, isTrue);
    expect(week.summary(), isNull);
  });
}
