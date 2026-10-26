import 'calendar.dart';

/// Règlement VS-R-2006-44, art. 9.21 : pas de stationnement dans les rues
/// et les stationnements publics de 0 h à 7 h, du 15 novembre au 1er avril.
///
/// Sur quelques tronçons commerciaux des centres-villes, l'interdiction ne
/// commence qu'à 3 h. Tant qu'on n'a pas la liste géolocalisée, on affiche
/// minuit partout : mieux vaut prévenir trop tôt que trop tard.
class WinterParking {
  const WinterParking();

  /// 30 $ d'amende et 15 $ de frais.
  static const fine = 45;
  static const endsAtMinute = 7 * 60;

  /// L'interdiction s'applique-t-elle pendant la nuit qui commence ce jour-là à 0 h ?
  bool appliesOn(DateTime day) {
    final m = day.month, d = day.day;
    return (m == 11 && d >= 15) || m == 12 || m <= 3 || (m == 4 && d == 1);
  }

  bool inForceAt(DateTime t) => appliesOn(t) && minuteOfDay(t) < endsAtMinute;

  /// Ce soir, à minuit, ce sera interdit.
  bool appliesTonight(DateTime t) => appliesOn(addDays(t, 1));

  /// Prochain début de saison à partir de [t].
  DateTime nextSeasonStart(DateTime t) {
    final thisYear = DateTime(t.year, 11, 15);
    return startOfDay(t).isAfter(thisYear) ? DateTime(t.year + 1, 11, 15) : thisYear;
  }
}
