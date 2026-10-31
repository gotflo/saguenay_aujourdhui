import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

void main() {
  // Calendrier 2026 du 201, rue Racine Est, tel que publié par la Ville.
  final racine = Demo.place('racine').collection;

  test('les ordures passent un lundi sur deux', () {
    expect(racine.on(DateTime(2026, 11, 2)), [WasteStream.garbage]);
    expect(racine.on(DateTime(2026, 11, 9)), isEmpty);
    expect(racine.on(DateTime(2026, 11, 16)), [WasteStream.garbage]);
  });

  test('le compost passe chaque semaine en été, aux deux semaines ensuite', () {
    expect(racine.on(DateTime(2026, 7, 10)), [WasteStream.compost]);
    expect(racine.on(DateTime(2026, 7, 17)), [WasteStream.compost]);
    expect(racine.on(DateTime(2026, 11, 6)), [WasteStream.compost]);
    expect(racine.on(DateTime(2026, 11, 13)), isEmpty);
  });

  test('la semaine d’été du compost commence le 4 mai 2026, pas le 8', () {
    // Zone de compost du lundi : le lundi 4 mai 2026 est déjà une semaine d’été
    // (hebdomadaire), comme au calendrier de la Ville. L’ancre du 11 mai fait que
    // le 4 mai n’est pas un passage du cycle de deux semaines : seule la règle
    // d’été peut le rendre vrai.
    final compostLundi = CollectionRule(
      weekday: DateTime.monday,
      anchor: DateTime(2026, 5, 11),
      weeklyInSummer: true,
    );
    expect(compostLundi.occursOn(DateTime(2026, 5, 4)), isTrue);
    // Avant la période d’été et hors du cycle de deux semaines : rien.
    expect(compostLundi.occursOn(DateTime(2026, 4, 20)), isFalse);
  });

  test('la prochaine collecte après le 25 octobre est le recyclage du mardi', () {
    final p = racine.next(DateTime(2026, 10, 25, 20));
    expect(p?.day, DateTime(2026, 10, 27));
    expect(p?.streams, [WasteStream.recycling]);
  });

  test('on ne devine rien au-delà du calendrier publié', () {
    expect(racine.next(DateTime(2026, 12, 29)), isNull);
    expect(racine.on(DateTime(2027, 1, 4)), isEmpty);
  });

  test('upcoming enchaîne les collectes', () {
    final days = racine.upcoming(DateTime(2026, 11, 1), count: 3).map((p) => p.day.day);
    expect(days, [2, 6, 10]);
  });
}
