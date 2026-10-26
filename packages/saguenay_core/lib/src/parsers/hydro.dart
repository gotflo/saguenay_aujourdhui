import 'dart:convert';

import '../power.dart';

/// Pannes en cours d'Hydro-Québec (`bismarkers{version}.json`), licence CC BY-NC 4.0.
///
/// Chaque panne est une ligne de tableau :
/// `[clients, début, fin prévue, "P", "[lon, lat]", statut, -, cause, municipalité, message]`.
/// Les heures sont locales. Une fin vide veut dire « pas encore estimée ».
List<PowerOutage> parseOutages(String body) {
  final json = jsonDecode(body);
  final rows = json is Map ? json['pannes'] : null;
  if (rows is! List) throw const FormatException('Liste des pannes absente');
  return [
    for (final r in rows)
      if (r is List && r.length >= 5)
        if (_point(r[4]) case (final lon, final lat))
          if (r[0] case final int customers)
            if (_time(r[1]) case final start?)
              PowerOutage(
                customers: customers,
                start: start,
                end: _time(r[2]),
                lon: lon,
                lat: lat,
                cause: r.length > 7 ? causeLabel(r[7]) : null,
              ),
  ];
}

/// Interruptions planifiées (`aipmarkers{version}.json`).
///
/// `[clients, avis, début, fin, (début, fin) réelles, reportées, décalées, ..., "[lon, lat]"]`.
/// On retient la dernière paire de dates remplie : c'est l'horaire qui tient.
List<PowerOutage> parsePlannedInterruptions(String body) {
  final rows = jsonDecode(body);
  if (rows is! List) throw const FormatException('Liste des interruptions absente');
  final out = <PowerOutage>[];
  for (final r in rows) {
    if (r is! List || r.length < 10 || r[0] is! int) continue;
    final point = r.map(_point).whereType<(double, double)>().firstOrNull;
    if (point == null) continue;
    DateTime? start, end;
    for (var i = 2; i + 1 < 10; i += 2) {
      final s = _time(r[i]), e = _time(r[i + 1]);
      if (s != null && e != null) (start, end) = (s, e);
    }
    if (start == null) continue;
    out.add(
      PowerOutage(
        customers: r[0] as int,
        start: start,
        end: end,
        lon: point.$1,
        lat: point.$2,
        planned: true,
      ),
    );
  }
  return out;
}

String? causeLabel(Object? code) => switch (int.tryParse('$code')) {
  21 || 22 || 24 || 25 || 26 => 'conditions météo',
  31 || 32 || 33 || 34 || 41 || 42 || 43 || 44 || 54 || 55 || 56 || 57 => 'accident ou incident',
  51 => 'végétation',
  52 || 53 => 'animal',
  11 || 12 || 13 || 14 || 15 || 58 || 70 || 72 || 73 || 74 || 79 => 'bris d’équipement',
  _ => null,
};

(double, double)? _point(Object? raw) {
  if (raw is! String || !raw.startsWith('[')) return null;
  try {
    final v = jsonDecode(raw);
    if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
      final lon = (v[0] as num).toDouble(), lat = (v[1] as num).toDouble();
      if (lat.abs() <= 90 && lon.abs() <= 180) return (lon, lat);
    }
  } on FormatException {
    return null;
  }
  return null;
}

DateTime? _time(Object? raw) => raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
