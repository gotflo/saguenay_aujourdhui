import 'geo.dart';
import 'power.dart' show distanceKm;

// Qualité de l'air ------------------------------------------------------------------

/// L'indice de la qualité de l'air (IQA) du Québec : bon jusqu'à 25,
/// acceptable jusqu'à 50, mauvais au-delà.
enum AirLevel {
  good('Bon'),
  acceptable('Acceptable'),
  poor('Mauvais');

  const AirLevel(this.label);

  final String label;
}

/// La dernière mesure horaire d'une station du ministère de l'Environnement.
class AirReading {
  const AirReading({
    required this.station,
    required this.name,
    required this.lat,
    required this.lon,
    required this.index,
    required this.at,
  });

  factory AirReading.fromJson(Map<String, Object?> json) => AirReading(
    station: json['station'] as String,
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    index: json['index'] as int,
    at: DateTime.parse(json['at'] as String),
  );

  final String station;

  /// « Saguenay - Parc Powell ».
  final String name;
  final double lat;
  final double lon;
  final int index;
  final DateTime at;

  AirLevel get level => index > 50
      ? AirLevel.poor
      : index > 25
      ? AirLevel.acceptable
      : AirLevel.good;

  /// « Parc Powell » plutôt que « Saguenay - Parc Powell ».
  String get shortName => name.split(' - ').last.trim();

  Map<String, Object?> toJson() => {
    'station': station,
    'name': name,
    'lat': lat,
    'lon': lon,
    'index': index,
    'at': at.toIso8601String(),
  };
}

class AirSnapshot {
  const AirSnapshot({required this.takenAt, required this.readings});

  factory AirSnapshot.fromJson(Map<String, Object?> json) => AirSnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    readings: [
      for (final r in (json['readings'] as List?) ?? const [])
        AirReading.fromJson((r as Map).cast<String, Object?>()),
    ],
  );

  final DateTime takenAt;
  final List<AirReading> readings;

  /// La mesure de la station la plus proche, si elle a moins de trois heures.
  AirReading? nearest(double lat, double lon, DateTime now) {
    AirReading? best;
    for (final r in readings) {
      if (now.difference(r.at) > const Duration(hours: 3)) continue;
      if (best == null ||
          distanceKm(lat, lon, r.lat, r.lon) < distanceKm(lat, lon, best.lat, best.lon)) {
        best = r;
      }
    }
    return best;
  }

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'readings': [for (final r in readings) r.toJson()],
  };
}

// Interdictions de feux ------------------------------------------------------------

/// Une mesure préventive du ministère de la Sécurité intérieure contre les feux
/// de forêt, sur une zone. « AUCUNE » veut dire qu'aucune interdiction ne s'applique.
class FireBan {
  const FireBan({required this.measure, required this.since, required this.rings});

  factory FireBan.fromJson(Map<String, Object?> json) => FireBan(
    measure: json['measure'] as String,
    since: switch (json['since']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    rings: readLonLatLists(json['rings']),
  );

  final String measure;
  final DateTime? since;
  final List<List<LonLat>> rings;

  bool get active => !measure.trim().toUpperCase().startsWith('AUCUNE');

  /// « Interdiction de faire des feux à ciel ouvert en forêt ou à proximité ».
  String get description {
    final dash = measure.indexOf(' - ');
    return dash < 0 ? measure.trim() : measure.substring(dash + 3).trim();
  }

  bool covers(double lat, double lon) => insideRings(rings, lat, lon);

  Map<String, Object?> toJson() => {
    'measure': measure,
    if (since != null) 'since': since!.toIso8601String(),
    'rings': writeLonLatLists(rings),
  };
}

class FireBanSnapshot {
  const FireBanSnapshot({required this.takenAt, required this.bans});

  factory FireBanSnapshot.fromJson(Map<String, Object?> json) => FireBanSnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    bans: [
      for (final b in (json['bans'] as List?) ?? const [])
        FireBan.fromJson((b as Map).cast<String, Object?>()),
    ],
  );

  final DateTime takenAt;
  final List<FireBan> bans;

  /// L'interdiction en vigueur qui couvre l'adresse, s'il y en a une.
  FireBan? at(double lat, double lon) =>
      bans.where((b) => b.active && b.covers(lat, lon)).firstOrNull;

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'bans': [for (final b in bans) b.toJson()],
  };
}

// Pointes d'Hydro-Québec -----------------------------------------------------------

/// Une période de pointe hivernale annoncée par Hydro-Québec aux clients
/// résidentiels : le Crédit hivernal (CPC-D) et le tarif Flex D (TPC-DPC)
/// partagent souvent les mêmes heures.
class PeakEvent {
  const PeakEvent({required this.start, required this.end, required this.offers});

  factory PeakEvent.fromJson(Map<String, Object?> json) => PeakEvent(
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    offers: {for (final o in (json['offers'] as List?) ?? const []) '$o'},
  );

  final DateTime start;
  final DateTime end;
  final Set<String> offers;

  static String offerLabel(String code) => switch (code) {
    'CPC-D' => 'Crédit hivernal',
    'TPC-DPC' => 'Flex D',
    _ => code,
  };

  /// « Crédit hivernal et Flex D ».
  String get offersLabel => (offers.toList()..sort()).map(offerLabel).join(' et ');

  String get key => start.toUtc().toIso8601String();

  bool activeAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  Map<String, Object?> toJson() => {
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'offers': offers.toList()..sort(),
  };
}

class PeakSnapshot {
  const PeakSnapshot({required this.takenAt, required this.events});

  factory PeakSnapshot.fromJson(Map<String, Object?> json) => PeakSnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    events: [
      for (final e in (json['events'] as List?) ?? const [])
        PeakEvent.fromJson((e as Map).cast<String, Object?>()),
    ],
  );

  final DateTime takenAt;
  final List<PeakEvent> events;

  /// La pointe en cours, ou la prochaine dans les 36 heures.
  PeakEvent? next(DateTime now) {
    PeakEvent? best;
    for (final e in events) {
      if (!now.isBefore(e.end) || e.start.difference(now) > const Duration(hours: 36)) continue;
      if (best == null || e.start.isBefore(best.start)) best = e;
    }
    return best;
  }

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'events': [for (final e in events) e.toJson()],
  };
}
