import 'dart:math' as math;

/// Une panne en cours, ou une interruption planifiée par Hydro-Québec.
class PowerOutage {
  const PowerOutage({
    required this.customers,
    required this.start,
    required this.lat,
    required this.lon,
    this.end,
    this.planned = false,
    this.cause,
  });

  factory PowerOutage.fromJson(Map<String, Object?> json) => PowerOutage(
    customers: json['customers'] as int,
    start: DateTime.parse(json['start'] as String),
    end: switch (json['end']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    planned: json['planned'] as bool? ?? false,
    cause: json['cause'] as String?,
  );

  /// Clients privés d'électricité.
  final int customers;
  final DateTime start;

  /// Retour prévu du courant. Vide quand Hydro-Québec ne l'a pas encore estimé.
  final DateTime? end;

  /// Centre approximatif du secteur touché.
  final double lat;
  final double lon;
  final bool planned;

  /// « bris d'équipement », « conditions météo »...
  final String? cause;

  /// Rayon approximatif du secteur : plus il y a de clients, plus il est grand.
  double get radiusKm => math.min(8, 1 + math.sqrt(customers) / 10);

  bool covers(double lat, double lon) => distanceKm(this.lat, this.lon, lat, lon) <= radiusKm;

  bool activeAt(DateTime t, {required DateTime takenAt}) {
    if (t.isBefore(start)) return false;
    final e = end;
    // Sans heure de retour, on ne s'avance pas au-delà de trois heures.
    if (e == null) return t.isBefore(takenAt.add(const Duration(hours: 3)));
    return t.isBefore(e);
  }

  Map<String, Object?> toJson() => {
    'customers': customers,
    'start': start.toIso8601String(),
    'end': end?.toIso8601String(),
    'lat': lat,
    'lon': lon,
    'planned': planned,
    'cause': cause,
  };
}

class PowerSnapshot {
  const PowerSnapshot({required this.takenAt, this.outages = const []});

  factory PowerSnapshot.fromJson(Map<String, Object?> json) => PowerSnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    outages: [
      for (final o in (json['outages'] as List?) ?? const [])
        PowerOutage.fromJson((o as Map).cast<String, Object?>()),
    ],
  );

  final DateTime takenAt;
  final List<PowerOutage> outages;

  bool isStaleAt(DateTime now) => now.difference(takenAt) > const Duration(hours: 2);

  /// Les pannes et interruptions dont le secteur couvre ces coordonnées.
  Iterable<PowerOutage> near(double lat, double lon) => outages.where((o) => o.covers(lat, lon));

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'outages': [for (final o in outages) o.toJson()],
  };
}

/// Distance à vol d'oiseau, en kilomètres.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
