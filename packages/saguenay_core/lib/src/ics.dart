import 'calendar.dart';
import 'collection.dart';
import 'parking.dart';
import 'place.dart';
import 'power.dart';

/// Un fichier iCalendar (.ics) des collectes et des dates d'hiver à venir,
/// à ouvrir dans Google Agenda ou Calendrier. Chaque collecte a un rappel
/// la veille au soir.
String calendarExport(
  Place place,
  DateTime from, {
  int days = 120,
  PowerSnapshot? power,
  DateTime? stamp,
}) {
  final now = (stamp ?? DateTime.now()).toUtc();
  final out = StringBuffer()
    ..write('BEGIN:VCALENDAR\r\n')
    ..write('VERSION:2.0\r\n')
    ..write('PRODID:-//Saguenay Aujourd’hui//FR\r\n')
    ..write('CALSCALE:GREGORIAN\r\n')
    ..write('X-WR-CALNAME:${_escape('Collectes · ${place.label}')}\r\n');

  void event(
    String uid,
    String summary, {
    required DateTime day,
    DateTime? startTime,
    DateTime? endTime,
    String? alarm,
  }) {
    out
      ..write('BEGIN:VEVENT\r\n')
      ..write('UID:$uid@saguenay-aujourdhui\r\n')
      ..write('DTSTAMP:${_utc(now)}\r\n');
    if (startTime != null && endTime != null) {
      out
        ..write('DTSTART;TZID=America/Toronto:${_local(startTime)}\r\n')
        ..write('DTEND;TZID=America/Toronto:${_local(endTime)}\r\n');
    } else {
      out
        ..write('DTSTART;VALUE=DATE:${_date(day)}\r\n')
        ..write('DTEND;VALUE=DATE:${_date(addDays(day, 1))}\r\n');
    }
    out.write('SUMMARY:${_escape(summary)}\r\n');
    if (alarm != null) {
      out
        ..write('BEGIN:VALARM\r\n')
        ..write('ACTION:DISPLAY\r\n')
        ..write('DESCRIPTION:${_escape(alarm)}\r\n')
        // La veille à 19 h : cinq heures avant minuit.
        ..write('TRIGGER:-PT5H\r\n')
        ..write('END:VALARM\r\n');
    }
    out.write('END:VEVENT\r\n');
  }

  final first = startOfDay(from);
  const parking = WinterParking();
  for (var n = 0; n < days; n++) {
    final day = addDays(first, n);
    final streams = place.collection.on(day);
    if (streams.isNotEmpty) {
      final names = streams.map((s) => s.label).join(' et ');
      event(
        'collecte-${_date(day)}',
        'Collecte : $names',
        day: day,
        alarm: 'Sors ${streams.map((s) => s.bin).join(' et ')} ce soir',
      );
    }
    if (!parking.appliesOn(day) && parking.appliesOn(addDays(day, 1))) {
      event('hiver-${_date(day)}', 'Première nuit sans auto dans la rue', day: day);
    }
    if (parking.appliesOn(day) && !parking.appliesOn(addDays(day, 1))) {
      event('fin-hiver-${_date(day)}', 'Dernière nuit d’interdiction de stationnement', day: day);
    }
  }
  final lat = place.lat, lon = place.lon;
  if (power != null && lat != null && lon != null) {
    for (final o in power.near(lat, lon)) {
      final end = o.end;
      if (!o.planned || end == null || end.isBefore(from)) continue;
      event(
        'coupure-${o.start.millisecondsSinceEpoch}',
        'Courant coupé (Hydro-Québec)',
        day: o.start,
        startTime: o.start,
        endTime: end,
      );
    }
  }
  out.write('END:VCALENDAR\r\n');
  return out.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';
String _local(DateTime d) => '${_date(d)}T${_two(d.hour)}${_two(d.minute)}00';
String _utc(DateTime d) => '${_local(d.toUtc())}Z';
String _escape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\n', r'\n');

/// Pour les tests : une collecte de ce jour figure-t-elle dans le fichier ?
bool calendarHasCollection(String ics, DateTime day, List<WasteStream> streams) =>
    ics.contains('DTSTART;VALUE=DATE:${_date(day)}') &&
    ics.contains('Collecte : ${streams.map((s) => s.label).join(' et ')}');
