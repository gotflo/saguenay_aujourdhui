import 'calendar.dart';

class Departure {
  const Departure(this.minute, this.route, this.headsign, {this.tripId, this.stopId});

  factory Departure.fromJson(Map<String, Object?> json) => Departure(
    json['m'] as int,
    json['r'] as String,
    json['h'] as String,
    tripId: json['t'] as String?,
    stopId: json['s'] as String?,
  );

  /// Minute de la journée (7 h 46 = 466).
  final int minute;
  final String route;
  final String headsign;

  /// Pour relier le départ au temps réel de la STS.
  final String? tripId;
  final String? stopId;

  Map<String, Object?> toJson() => {
    'm': minute,
    'r': route,
    'h': headsign,
    't': ?tripId,
    's': ?stopId,
  };
}

/// L'horaire prévu d'un arrêt, tiré du flux GTFS de la STS.
///
/// Deux formes : trois listes types (semaine, samedi, dimanche) pour la
/// démo, ou une liste par date ([byDate]) quand on lit le vrai flux, qui
/// tient compte des jours fériés.
class StopSchedule {
  const StopSchedule({
    required this.name,
    required this.validFrom,
    required this.validTo,
    this.weekday = const [],
    this.saturday = const [],
    this.sunday = const [],
    this.byDate,
  });

  factory StopSchedule.fromJson(Map<String, Object?> json) => StopSchedule(
    name: json['name'] as String,
    validFrom: DateTime.parse(json['validFrom'] as String),
    validTo: DateTime.parse(json['validTo'] as String),
    byDate: {
      for (final MapEntry(:key, :value) in ((json['byDate'] as Map?) ?? const {}).entries)
        int.parse('$key'): [
          for (final d in value as List) Departure.fromJson((d as Map).cast<String, Object?>()),
        ],
    },
  );

  final String name;
  final List<Departure> weekday;
  final List<Departure> saturday;
  final List<Departure> sunday;

  /// Numéro du jour ([dayNumber]) → départs triés.
  final Map<int, List<Departure>>? byDate;

  /// Période couverte par le flux téléchargé.
  final DateTime validFrom;
  final DateTime validTo;

  bool covers(DateTime t) {
    final d = startOfDay(t);
    return !d.isBefore(validFrom) && !d.isAfter(validTo);
  }

  List<Departure> forDay(DateTime t) {
    final dates = byDate;
    if (dates != null) return dates[dayNumber(t)] ?? const [];
    return switch (t.weekday) {
      DateTime.saturday => saturday,
      DateTime.sunday => sunday,
      _ => weekday,
    };
  }

  /// Les prochains départs de la journée, ou `null` hors de la période connue.
  List<Departure>? after(DateTime t, {int count = 3}) {
    if (!covers(t)) return null;
    final m = minuteOfDay(t);
    return forDay(t).where((d) => d.minute >= m).take(count).toList();
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'validFrom': validFrom.toIso8601String(),
    'validTo': validTo.toIso8601String(),
    'byDate': {
      for (final MapEntry(:key, :value) in (byDate ?? const <int, List<Departure>>{}).entries)
        '$key': [for (final d in value) d.toJson()],
    },
  };
}

/// Le temps réel de la STS : l'avance ou le retard de chaque voyage.
class TransitRealtime {
  const TransitRealtime({required this.takenAt, required this.trips});

  final DateTime takenAt;

  /// Identifiant du voyage → retard par arrêt (en secondes), et retard du
  /// voyage sous la clé vide quand le flux ne donne que celui-là.
  final Map<String, Map<String, int>> trips;

  /// Le retard de ce départ, en secondes, ou `null` si la STS n'en dit rien.
  int? delayFor(Departure d) {
    final trip = trips[d.tripId];
    if (trip == null) return null;
    return trip[d.stopId] ?? trip[''];
  }

  /// Au-delà de trois minutes, le temps réel n'en est plus.
  bool isFreshAt(DateTime now) => now.difference(takenAt).abs() < const Duration(minutes: 3);
}
