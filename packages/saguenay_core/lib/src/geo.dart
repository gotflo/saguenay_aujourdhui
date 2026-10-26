import 'dart:math' as math;

/// Un point en degrés : longitude, latitude (l'ordre des fichiers GeoJSON et ArcGIS).
typedef LonLat = (double, double);

/// Le point est-il dans un des anneaux ? Lancer de rayon, assez précis à
/// l'échelle d'une rue. Les trous (anneaux intérieurs) comptent aussi :
/// un point dans un trou est dans un nombre pair d'anneaux.
bool insideRings(List<List<LonLat>> rings, double lat, double lon) {
  var inside = false;
  for (final ring in rings) {
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final (xi, yi) = ring[i];
      final (xj, yj) = ring[j];
      if ((yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
  }
  return inside;
}

/// Distance en mètres entre un point et le tracé le plus proche.
double distanceToPaths(List<List<LonLat>> paths, double lat, double lon) {
  // Projection locale : à Saguenay, un degré de longitude vaut environ 74 km.
  final kx = 111320 * math.cos(lat * math.pi / 180), ky = 110540.0;
  var best = double.infinity;
  for (final path in paths) {
    if (path.length == 1) {
      final (x, y) = path.first;
      best = math.min(best, math.sqrt(math.pow((x - lon) * kx, 2) + math.pow((y - lat) * ky, 2)));
      continue;
    }
    for (var i = 0; i + 1 < path.length; i++) {
      final (x1, y1) = path[i];
      final (x2, y2) = path[i + 1];
      final ax = (x1 - lon) * kx, ay = (y1 - lat) * ky;
      final bx = (x2 - lon) * kx, by = (y2 - lat) * ky;
      final dx = bx - ax, dy = by - ay;
      final len = dx * dx + dy * dy;
      final t = len == 0 ? 0.0 : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      best = math.min(best, math.sqrt(px * px + py * py));
    }
  }
  return best;
}

/// « Rue Saint-Éloi » et « RUE ST-ELOI » deviennent la même clé.
String streetKey(String street) {
  var s = street.toLowerCase().trim();
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', //
    'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'œ': 'oe', '’': ' ', "'": ' ',
  };
  s = s.split('').map((c) => accents[c] ?? c).join();
  s = s.replaceAll(RegExp(r'[-.,]'), ' ');
  s = s.replaceAllMapped(RegExp(r'\b(st|ste)\b'), (m) => m[1] == 'st' ? 'saint' : 'sainte');
  s = s.replaceAll(RegExp(r'\bboul\b'), 'boulevard').replaceAll(RegExp(r'\bch\b'), 'chemin');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<List<LonLat>> readLonLatLists(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final part in raw)
      if (part is List)
        [
          for (final p in part)
            if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
              ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
  ];
}

List<List<List<double>>> writeLonLatLists(List<List<LonLat>> parts) => [
  for (final part in parts)
    [
      for (final (x, y) in part) [x, y],
    ],
];
