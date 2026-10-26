// Toutes les heures du projet sont des heures « murales » de Saguenay.
// On compte les jours en UTC pour que les changements d'heure ne décalent rien.

const _msPerDay = Duration.millisecondsPerDay;

/// Numéro du jour depuis le 1er janvier 1970.
int dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ _msPerDay;

/// Inverse de [dayNumber] : minuit, heure locale.
DateTime dateFromDayNumber(int n) {
  final u = DateTime.fromMillisecondsSinceEpoch(n * _msPerDay, isUtc: true);
  return DateTime(u.year, u.month, u.day);
}

int minuteOfDay(DateTime d) => d.hour * 60 + d.minute;

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

DateTime atMinute(DateTime day, int minute) =>
    DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Du lundi au vendredi, de 6 h 15 à 9 h et de 15 h 15 à 18 h.
bool isRushHour(DateTime t) {
  if (t.weekday > DateTime.friday) return false;
  final m = minuteOfDay(t);
  return (m >= 375 && m < 540) || (m >= 915 && m < 1080);
}
