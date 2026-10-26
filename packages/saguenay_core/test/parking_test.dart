import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

void main() {
  const parking = WinterParking();

  test('la saison va du 15 novembre au 1er avril inclus', () {
    expect(parking.appliesOn(DateTime(2026, 11, 14)), isFalse);
    expect(parking.appliesOn(DateTime(2026, 11, 15)), isTrue);
    expect(parking.appliesOn(DateTime(2027, 2, 10)), isTrue);
    expect(parking.appliesOn(DateTime(2027, 4, 1)), isTrue);
    expect(parking.appliesOn(DateTime(2027, 4, 2)), isFalse);
  });

  test('l’interdiction finit à 7 h', () {
    expect(parking.inForceAt(DateTime(2026, 11, 16, 6, 59)), isTrue);
    expect(parking.inForceAt(DateTime(2026, 11, 16, 7)), isFalse);
  });

  test('le 14 novembre au soir, c’est déjà interdit à minuit', () {
    expect(parking.appliesTonight(DateTime(2026, 11, 14, 21, 30)), isTrue);
  });

  test('prochain début de saison', () {
    expect(parking.nextSeasonStart(DateTime(2026, 10, 25)), DateTime(2026, 11, 15));
    expect(parking.nextSeasonStart(DateTime(2027, 4, 2)), DateTime(2027, 11, 15));
  });
}
