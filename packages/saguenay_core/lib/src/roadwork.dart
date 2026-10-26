import 'calendar.dart';
import 'geo.dart';

class Roadwork {
  const Roadwork({
    required this.street,
    required this.shortName,
    required this.status,
    required this.details,
    required this.start,
    required this.end,
    this.dailyFromMinute,
    this.dailyToMinute,
    this.sector,
    this.paths = const [],
  });

  factory Roadwork.fromJson(Map<String, Object?> json) => Roadwork(
    street: json['street'] as String,
    shortName: json['shortName'] as String,
    status: json['status'] as String,
    details: json['details'] as String? ?? '',
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    dailyFromMinute: json['dailyFromMinute'] as int?,
    dailyToMinute: json['dailyToMinute'] as int?,
    sector: json['sector'] as String?,
    paths: readLonLatLists(json['paths']),
  );

  /// « Rue Saint-Pierre ».
  final String street;

  /// « Saint-Pierre », pour une tuile.
  final String shortName;

  /// « circulation locale », « fermée », « à contresens »...
  final String status;
  final String details;
  final DateTime start;
  final DateTime end;

  /// Pour les chantiers de jour seulement (7 h à 17 h, par exemple).
  final int? dailyFromMinute;
  final int? dailyToMinute;

  /// « Chicoutimi », « Jonquière »...
  final String? sector;

  /// Le tracé du chantier, tel que la Ville le dessine.
  final List<List<LonLat>> paths;

  bool activeAt(DateTime t) {
    if (t.isBefore(start) || !t.isBefore(end)) return false;
    final from = dailyFromMinute, to = dailyToMinute;
    if (from == null || to == null) return true;
    final m = minuteOfDay(t);
    return m >= from && m < to;
  }

  bool isOverAt(DateTime t) => !t.isBefore(end);

  /// En mètres, ou l'infini quand on n'a pas le tracé.
  double distanceTo(double lat, double lon) =>
      paths.isEmpty ? double.infinity : distanceToPaths(paths, lat, lon);

  Map<String, Object?> toJson() => {
    'street': street,
    'shortName': shortName,
    'status': status,
    'details': details,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'dailyFromMinute': dailyFromMinute,
    'dailyToMinute': dailyToMinute,
    'sector': sector,
    'paths': writeLonLatLists(paths),
  };
}

/// Un chantier vu depuis une adresse : sur sa rue, ou ailleurs dans l'arrondissement.
class NearbyRoadwork {
  const NearbyRoadwork(this.work, {required this.onMyStreet});

  final Roadwork work;
  final bool onMyStreet;
}

class RoadworkSnapshot {
  const RoadworkSnapshot({required this.takenAt, required this.works});

  factory RoadworkSnapshot.fromJson(Map<String, Object?> json) => RoadworkSnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    works: [
      for (final w in (json['works'] as List?) ?? const [])
        Roadwork.fromJson((w as Map).cast<String, Object?>()),
    ],
  );

  final DateTime takenAt;
  final List<Roadwork> works;

  /// Les chantiers qui comptent pour cette adresse : ceux de sa rue, puis les
  /// plus proches, à moins de 1,5 km.
  List<NearbyRoadwork> near(double lat, double lon, {required String street, int max = 4}) {
    final key = streetKey(street);
    final scored = <(double, NearbyRoadwork)>[];
    for (final w in works) {
      final d = w.distanceTo(lat, lon);
      final mine = d < 80 || (d < 600 && streetKey(w.street) == key);
      if (mine || d < 1500) scored.add((d, NearbyRoadwork(w, onMyStreet: mine)));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, n) in scored.take(max)) n];
  }

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'works': [for (final w in works) w.toJson()],
  };
}
