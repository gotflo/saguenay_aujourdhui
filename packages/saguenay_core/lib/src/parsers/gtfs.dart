import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';

import '../calendar.dart';
import '../power.dart';
import '../transit.dart';

class GtfsStop {
  const GtfsStop(this.id, this.name, this.lat, this.lon);

  final String id;
  final String name;
  final double lat;
  final double lon;
}

/// Le flux GTFS de la STS (`saguenay.tmix.se/Tmix.Cap.TdExport.WebApi/gtfs/`),
/// un zip d'environ 700 Ko. Le flux n'a pas de `calendar.txt` : les jours de
/// service sont tous dans `calendar_dates.txt`.
class GtfsFeed {
  GtfsFeed._(this.stops, this.validFrom, this.validTo, this._files);

  factory GtfsFeed.parse(List<int> zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    String file(String name) {
      final f = archive.findFile(name);
      if (f == null) throw FormatException('$name absent du flux');
      var text = utf8.decode(f.content, allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      return text;
    }

    final stops = <GtfsStop>[];
    for (final row in _rows(file('stops.txt'))) {
      final lat = double.tryParse(row['stop_lat'] ?? ''),
          lon = double.tryParse(row['stop_lon'] ?? '');
      final id = row['stop_id'];
      if (id == null || lat == null || lon == null) continue;
      stops.add(GtfsStop(id, (row['stop_name'] ?? id).trim(), lat, lon));
    }

    DateTime? from, to;
    if (archive.findFile('feed_info.txt') != null) {
      final info = _rows(file('feed_info.txt')).firstOrNull;
      from = _date(info?['feed_start_date']);
      to = _date(info?['feed_end_date']);
    }
    final files = {
      for (final name in ['trips.txt', 'routes.txt', 'calendar_dates.txt', 'stop_times.txt'])
        name: file(name),
    };
    if (from == null || to == null) {
      final dates = _rows(
        files['calendar_dates.txt']!,
      ).map((r) => _date(r['date'])).whereType<DateTime>();
      from ??= dates.reduce((a, b) => a.isBefore(b) ? a : b);
      to ??= dates.reduce((a, b) => a.isAfter(b) ? a : b);
    }
    return GtfsFeed._(stops, from, to, files);
  }

  final List<GtfsStop> stops;
  final DateTime validFrom;
  final DateTime validTo;
  final Map<String, String> _files;

  /// Les arrêts à moins de [withinMeters], du plus proche au plus loin. Les
  /// deux côtés de la rue comptent : on garde les deux sens.
  List<GtfsStop> nearestStops(double lat, double lon, {int max = 2, double withinMeters = 600}) =>
      nearestOf(stops, lat, lon, max: max, withinMeters: withinMeters);

  /// L'horaire de ces arrêts, date par date.
  StopSchedule schedule(List<GtfsStop> at, {required DateTime from, int days = 60}) {
    final first = dayNumber(from);
    final last = math.min(first + days, dayNumber(validTo));
    return StopSchedule(
      name: at.isEmpty ? '' : at.first.name,
      validFrom: dateFromDayNumber(first),
      validTo: dateFromDayNumber(last),
      byDate: _departures({for (final s in at) s.id}, first, last),
    );
  }

  /// Les départs de tous les arrêts pour la journée de [from] : de quoi
  /// trouver l'arrêt le plus proche partout en ville sans relire le flux à
  /// chaque pas.
  TransitDay day(DateTime from) {
    final d = dayNumber(from);
    final byStop = <String, List<Departure>>{};
    if (d <= dayNumber(validTo)) {
      for (final dep in _departures(null, d, d)[d] ?? const <Departure>[]) {
        byStop.putIfAbsent(dep.stopId ?? '', () => []).add(dep);
      }
    }
    return TransitDay(date: dateFromDayNumber(d), stops: stops, byStop: byStop);
  }

  /// Les départs de ces arrêts (de tous si [ids] est nul), date par date.
  Map<int, List<Departure>> _departures(Set<String>? ids, int first, int last) {
    final routes = {
      for (final r in _rows(_files['routes.txt']!))
        r['route_id']: r['route_short_name'] ?? r['route_id'],
    };
    final trips = <String, (String service, String route, String headsign)>{};
    for (final t in _rows(_files['trips.txt']!)) {
      final id = t['trip_id'], service = t['service_id'];
      if (id == null || service == null) continue;
      trips[id] = (
        service,
        routes[t['route_id']] ?? t['route_id'] ?? '',
        cleanHeadsign(t['trip_headsign'] ?? ''),
      );
    }
    final services = <String, Set<int>>{};
    for (final c in _rows(_files['calendar_dates.txt']!)) {
      final d = _date(c['date']);
      if (d == null || c['exception_type'] != '1') continue;
      services.putIfAbsent(c['service_id'] ?? '', () => {}).add(dayNumber(d));
    }

    final byDate = <int, List<Departure>>{};
    final keep = ids == null ? null : (Map<String, String> r) => ids.contains(r['stop_id']);
    for (final st in _rows(_files['stop_times.txt']!, keep: keep)) {
      final trip = trips[st['trip_id']];
      final minute = _minutes(st['departure_time'] ?? st['arrival_time']);
      if (trip == null || minute == null) continue;
      for (final day in services[trip.$1] ?? const <int>{}) {
        // Un départ à 24 h 30 appartient au lendemain, 0 h 30.
        final date = day + minute ~/ 1440;
        if (date < first || date > last) continue;
        byDate
            .putIfAbsent(date, () => [])
            .add(
              Departure(
                minute % 1440,
                trip.$2,
                trip.$3,
                tripId: st['trip_id'],
                stopId: st['stop_id'],
              ),
            );
      }
    }
    for (final list in byDate.values) {
      list.sort((a, b) => a.minute.compareTo(b.minute));
    }
    return byDate;
  }
}

/// Les arrêts à moins de [withinMeters] d'un point, du plus proche au plus loin.
List<GtfsStop> nearestOf(
  List<GtfsStop> stops,
  double lat,
  double lon, {
  int max = 2,
  double withinMeters = 600,
}) {
  final scored = [for (final s in stops) (distanceKm(lat, lon, s.lat, s.lon) * 1000, s)]
    ..sort((a, b) => a.$1.compareTo(b.$1));
  return [
    for (final (d, s) in scored.take(max))
      if (d <= withinMeters) s,
  ];
}

/// Une journée de départs pour tous les arrêts de la STS. Calculée une fois
/// par jour sur le téléphone ; trouver les arrêts proches d'une position ne
/// coûte ensuite presque rien, et la position ne quitte jamais le téléphone.
class TransitDay {
  const TransitDay({required this.date, required this.stops, required this.byStop});

  final DateTime date;
  final List<GtfsStop> stops;

  /// Identifiant de l'arrêt → départs triés.
  final Map<String, List<Departure>> byStop;

  /// L'horaire des deux arrêts les plus proches de ce point (les deux côtés
  /// de la rue), ou `null` s'il n'y en a pas à moins de 600 m.
  StopSchedule? around(double lat, double lon) {
    final near = nearestOf(stops, lat, lon);
    if (near.isEmpty) return null;
    final departures = [for (final s in near) ...?byStop[s.id]]
      ..sort((a, b) => a.minute.compareTo(b.minute));
    return StopSchedule(
      name: near.first.name,
      validFrom: date,
      validTo: date,
      byDate: {dayNumber(date): departures},
      aroundYou: true,
    );
  }
}

/// « Terminus Chioutimi vers Terminus La Baie » devient « La Baie » : la
/// destination seule, comme sur l'afficheur du bus.
String cleanHeadsign(String raw) {
  var s = raw.trim();
  final i = s.toLowerCase().lastIndexOf(' vers ');
  if (i >= 0) s = s.substring(i + 6);
  s = s
      .replaceFirst(RegExp(r'^terminus\s+', caseSensitive: false), '')
      .replaceAll('Chioutimi', 'Chicoutimi');
  return s.isEmpty ? raw.trim() : s[0].toUpperCase() + s.substring(1);
}

DateTime? _date(String? raw) {
  if (raw == null || raw.length != 8) return null;
  final y = int.tryParse(raw.substring(0, 4)),
      m = int.tryParse(raw.substring(4, 6)),
      d = int.tryParse(raw.substring(6));
  return y == null || m == null || d == null ? null : DateTime(y, m, d);
}

int? _minutes(String? raw) {
  final parts = raw?.trim().split(':');
  if (parts == null || parts.length < 2) return null;
  final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  return h == null || m == null ? null : h * 60 + m;
}

/// Lit un fichier CSV du GTFS, guillemets compris (« Bagot / C.Gaudreault »,
/// « "Racine, boul. Talbot" »). [keep] filtre tôt les lignes inutiles.
Iterable<Map<String, String>> _rows(String text, {bool Function(Map<String, String>)? keep}) sync* {
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty) return;
  final header = _fields(lines.first).map((h) => h.trim()).toList();
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final f = _fields(line);
    final row = {for (var i = 0; i < header.length && i < f.length; i++) header[i]: f[i]};
    if (keep == null || keep(row)) yield row;
  }
}

List<String> _fields(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}
