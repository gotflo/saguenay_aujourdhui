import '../roads.dart';

/// Conditions routières hivernales du ministère des Transports (service WFS
/// `ws.mapserver.transports.gouv.qc.ca/swtq`, couche `ms:conditions_routieres`,
/// sortie GeoJSON), licence CC BY 4.0. On garde les routes suivies.
List<RoadSegment> parseRoadConditions(Map<String, Object?> json) {
  final out = <RoadSegment>[];
  for (final f in (json['features'] as List?) ?? const []) {
    final p = f is Map ? (f['properties'] as Map?)?.cast<String, Object?>() : null;
    if (p == null) continue;
    final route = p['NumeroRoute'];
    if (route is! int || !RoadReport.routes.contains(route)) continue;
    out.add(
      RoadSegment(
        route: route,
        from: '${p['LocalisationDebutFR'] ?? ''}'.trim(),
        to: '${p['LocalisationFinFR'] ?? ''}'.trim(),
        surface: '${p['DescriptionEtatChausseeFR'] ?? 'Inconnue'}'.trim(),
        visibility: '${p['DescriptionVisibiliteFR'] ?? 'Inconnue'}'.trim(),
        surfaceCode: '${p['CodeEtatChaussee'] ?? ''}',
        since: p['EnVigueurDepuis'] is String
            ? DateTime.tryParse(p['EnVigueurDepuis'] as String)
            : null,
      ),
    );
  }
  out.sort(
    (a, b) => RoadReport.routes.indexOf(a.route).compareTo(RoadReport.routes.indexOf(b.route)),
  );
  return out;
}

/// Caméras de circulation (couche `ms:infos_cameras`). L'image elle-même
/// n'est pas ouverte : on renvoie vers la page de Québec 511.
List<TrafficCamera> parseCameras(Map<String, Object?> json) => [
  for (final f in (json['features'] as List?) ?? const [])
    if (f is Map)
      if ((f['properties'] as Map?)?.cast<String, Object?>() case final p?)
        if (f['geometry'] case {'coordinates': [final num lon, final num lat]})
          if (p['URL_FLUX_DONNEE'] case final String url when url.startsWith('https://'))
            TrafficCamera(
              id: '${p['IDEcamera'] ?? p['NumeroCamera']}',
              place: '${p['DescriptionLocalisationFr'] ?? ''}'.trim(),
              lat: lat.toDouble(),
              lon: lon.toDouble(),
              url: url,
            ),
];
