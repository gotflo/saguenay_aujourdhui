import '../environment.dart';
import '../geo.dart';

/// Dernières mesures de l'indice de la qualité de l'air, couche ArcGIS
/// `IQA_resultat_REST` du ministère de l'Environnement (licence CC BY 4.0).
/// `DATE_HEURE` est en millisecondes UTC.
List<AirReading> parseAirQuality(Map<String, Object?> json) {
  final out = <AirReading>[];
  for (final f in (json['features'] as List?) ?? const []) {
    final a = f is Map ? (f['attributes'] as Map?)?.cast<String, Object?>() : null;
    if (a == null) continue;
    final index = a['IQA'], lat = a['LATITUDE'], lon = a['LONGITUDE'], at = a['DATE_HEURE'];
    if (index is! int || lat is! num || lon is! num || at is! int) continue;
    out.add(
      AirReading(
        station: '${a['NO_STATION'] ?? ''}',
        name: '${a['NOM_STATION'] ?? ''}'.trim(),
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        index: index,
        at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).toLocal(),
      ),
    );
  }
  return out;
}

/// Interdictions de feux à ciel ouvert du ministère de la Sécurité intérieure (ex-Sécurité publique)
/// (service WFS `msp_interdiction_feu_ciel_ouvert_ifco`, GeoJSON, licence CC BY 4.0).
List<FireBan> parseFireBans(Map<String, Object?> json) {
  final out = <FireBan>[];
  for (final f in (json['features'] as List?) ?? const []) {
    if (f is! Map) continue;
    final p = (f['properties'] as Map?)?.cast<String, Object?>();
    final g = (f['geometry'] as Map?)?.cast<String, Object?>();
    final measure = p?['mes_prev'];
    if (measure is! String || g == null) continue;
    final rings = switch (g['type']) {
      'Polygon' => readLonLatLists(g['coordinates']),
      'MultiPolygon' => [
        for (final polygon in (g['coordinates'] as List?) ?? const []) ...readLonLatLists(polygon),
      ],
      _ => const <List<LonLat>>[],
    };
    if (rings.isEmpty) continue;
    out.add(
      FireBan(measure: measure, since: DateTime.tryParse('${p?['date_eff'] ?? ''}'), rings: rings),
    );
  }
  return out;
}

/// Événements de pointe d'Hydro-Québec (jeu `evenements-pointe`, licence
/// CC BY-NC 4.0). Les offres qui partagent les mêmes heures deviennent un
/// seul événement.
List<PeakEvent> parsePeakEvents(Map<String, Object?> json) {
  final byTime = <String, ({DateTime start, DateTime end, Set<String> offers})>{};
  for (final r in (json['results'] as List?) ?? const []) {
    if (r is! Map) continue;
    if ('${r['secteurclient'] ?? ''}'.toLowerCase() != 'residentiel') continue;
    final start = DateTime.tryParse('${r['datedebut'] ?? ''}');
    final end = DateTime.tryParse('${r['datefin'] ?? ''}');
    if (start == null || end == null || !end.isAfter(start)) continue;
    final key = '${start.toUtc().toIso8601String()}|${end.toUtc().toIso8601String()}';
    final slot = byTime.putIfAbsent(
      key,
      () => (start: start.toLocal(), end: end.toLocal(), offers: <String>{}),
    );
    slot.offers.add('${r['offre'] ?? ''}');
  }
  return [for (final s in byTime.values) PeakEvent(start: s.start, end: s.end, offers: s.offers)]
    ..sort((a, b) => a.start.compareTo(b.start));
}
