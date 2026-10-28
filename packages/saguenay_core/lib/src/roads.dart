import 'power.dart';

/// Un tronçon de route et son état, selon le ministère des Transports.
class RoadSegment {
  const RoadSegment({
    required this.route,
    required this.from,
    required this.to,
    required this.surface,
    required this.visibility,
    this.surfaceCode = '',
    this.since,
  });

  factory RoadSegment.fromJson(Map<String, Object?> json) => RoadSegment(
    route: json['route'] as int,
    from: json['from'] as String,
    to: json['to'] as String,
    surface: json['surface'] as String,
    visibility: json['visibility'] as String,
    surfaceCode: json['surfaceCode'] as String? ?? '',
    since: switch (json['since']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
  );

  final int route;

  /// « L'Étape », « Jonction de l'autoroute 70 et de la route 175 à Saguenay ».
  final String from;
  final String to;

  /// « Dégagée et sèche », « Partiellement enneigée »...
  final String surface;

  /// « Bonne », « Réduite »...
  final String visibility;
  final String surfaceCode;
  final DateTime? since;

  /// Chaussée sèche et bonne visibilité : rien à signaler.
  bool get isNormal =>
      surface.toLowerCase().contains('sèche') && visibility.toLowerCase().contains('bonne');

  /// Route fermée ou visibilité nulle : ça mérite la carte du haut.
  bool get isSevere {
    final s = '${surface.toLowerCase()} ${visibility.toLowerCase()}';
    return s.contains('fermée') || s.contains('nulle') || s.contains('glac');
  }

  Map<String, Object?> toJson() => {
    'route': route,
    'from': from,
    'to': to,
    'surface': surface,
    'visibility': visibility,
    'surfaceCode': surfaceCode,
    'since': since?.toIso8601String(),
  };
}

class TrafficCamera {
  const TrafficCamera({
    required this.id,
    required this.place,
    required this.lat,
    required this.lon,
    required this.url,
  });

  factory TrafficCamera.fromJson(Map<String, Object?> json) => TrafficCamera(
    id: json['id'] as String,
    place: json['place'] as String,
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    url: json['url'] as String,
  );

  final String id;

  /// « Route 172 à la hauteur de Saint-Fulgence (km 103) ».
  final String place;
  final double lat;
  final double lon;

  /// La page de Québec 511 qui montre l'image en direct.
  final String url;

  Map<String, Object?> toJson() => {'id': id, 'place': place, 'lat': lat, 'lon': lon, 'url': url};
}

/// Les routes qui comptent pour Saguenay, dont la 175 dans la réserve faunique des Laurentides.
class RoadReport {
  const RoadReport({required this.takenAt, required this.segments, this.cameras = const []});

  factory RoadReport.fromJson(Map<String, Object?> json) => RoadReport(
    takenAt: DateTime.parse(json['takenAt'] as String),
    segments: [
      for (final s in (json['segments'] as List?) ?? const [])
        RoadSegment.fromJson((s as Map).cast<String, Object?>()),
    ],
    cameras: [
      for (final c in (json['cameras'] as List?) ?? const [])
        TrafficCamera.fromJson((c as Map).cast<String, Object?>()),
    ],
  );

  /// Les routes suivies, dans l'ordre d'importance pour les gens d'ici.
  static const routes = [175, 170, 172, 169, 70, 372, 381];

  final DateTime takenAt;
  final List<RoadSegment> segments;
  final List<TrafficCamera> cameras;

  bool isStaleAt(DateTime now) => now.difference(takenAt) > const Duration(hours: 3);

  /// Le tronçon le plus inquiétant, s'il y en a un.
  RoadSegment? get worst {
    RoadSegment? best;
    for (final s in segments) {
      if (s.isNormal) continue;
      if (best == null ||
          (s.isSevere && !best.isSevere) ||
          routes.indexOf(s.route) < routes.indexOf(best.route)) {
        best = s;
      }
    }
    return best;
  }

  List<TrafficCamera> camerasNear(double lat, double lon, {int max = 3}) {
    final sorted = [...cameras]
      ..sort(
        (a, b) => distanceKm(lat, lon, a.lat, a.lon).compareTo(distanceKm(lat, lon, b.lat, b.lon)),
      );
    return sorted.take(max).toList();
  }

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'segments': [for (final s in segments) s.toJson()],
    'cameras': [for (final c in cameras) c.toJson()],
  };
}
