import 'calendar.dart';

const _days = [
  'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche', //
];
const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const _shortMonths = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', //
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// « 7 h », « 7 h 46 ».
String clockTime(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60) % 24;
  final m = minuteOfDay % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String clockTimeOf(DateTime d) => clockTime(minuteOfDay(d));

/// « dimanche 15 novembre », « mardi 1er décembre ».
String longDate(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day}${d.day == 1 ? 'er' : ''} ${_months[d.month - 1]}';

/// « mardi 27 oct. ».
String shortDate(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_shortMonths[d.month - 1]}';

String weekdayName(DateTime d) => _days[d.weekday - 1];

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String greeting(DateTime d) {
  final m = minuteOfDay(d);
  if (m < 300) return 'Bonne nuit';
  if (m < 720) return 'Bonjour';
  if (m < 1080) return 'Bon après-midi';
  return 'Bonsoir';
}

/// « maintenant », « dans 11 min », « dans 1 h 50 », ou l'heure si on la donne.
String inMinutes(int minutes, {int? atMinute}) {
  if (minutes <= 0) return 'maintenant';
  if (minutes < 60) return 'dans $minutes min';
  if (atMinute != null) return 'à ${clockTime(atMinute)}';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? 'dans $h h' : 'dans $h h ${m.toString().padLeft(2, '0')}';
}

/// « 18° », « -4° ».
String temperatureLabel(double celsius) => '${celsius.round()}°';

/// L'heure d'un relevé, avec le jour s'il ne date pas d'aujourd'hui :
/// « de 15 h 41 », « d’hier à 15 h 41 », « du mardi 27 oct. à 15 h 41 ».
String takenLabel(DateTime takenAt, DateTime now) {
  final days = dayNumber(now) - dayNumber(takenAt);
  if (days == 0) return 'de ${clockTimeOf(takenAt)}';
  if (days == 1) return 'd’hier à ${clockTimeOf(takenAt)}';
  return 'du ${shortDate(takenAt)} à ${clockTimeOf(takenAt)}';
}

/// Termine une phrase par un point, sauf si elle finit déjà par une abréviation
/// (« 27 oct. »).
String sentence(String s) => s.endsWith('.') ? s : '$s.';
