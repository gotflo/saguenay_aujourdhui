import '../geo.dart';
import '../roadwork.dart';
import '../water.dart';

/// Les couches ArcGIS de la Ville enregistrent l'heure locale comme si
/// c'était de l'UTC : un avis qui commence à 8 h arrive sous la forme 08:00Z.
DateTime arcgisWallTime(int millis) {
  final u = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

/// Couche « Avis d'aqueduc » (`COM_avis_aqueduc/.../FeatureServer/0/query?f=json`),
/// avec `outSR=4326` pour avoir les zones en degrés.
///
/// On ne lit volontairement pas les champs `created_by` et `updated_by` :
/// ils contiennent des matricules d'employés. Les avis supprimés ou marqués
/// « Inactif » (levés) sont écartés.
List<WaterNotice> parseWaterNotices(Map<String, Object?> json) => [
  for (final (a, g) in _features(json))
    if (a['avis_no'] case final String number)
      if (a['date_actif'] case final int start)
        if (a['deleted_at'] == null && _text(a['status']).toLowerCase() != 'inactif')
          WaterNotice(
            number: number,
            type: _noticeType(a['type_avis']),
            start: arcgisWallTime(start),
            end: a['date_fin'] is int ? arcgisWallTime(a['date_fin'] as int) : null,
            zone: _text(a['avis_desc']),
            rings: readLonLatLists(g?['rings']),
          ),
];

/// Couche « État de la circulation », la même source que « Chantiers - 511 »
/// sur Données Québec, avec les tracés.
List<Roadwork> parseRoadworks(Map<String, Object?> json) => [
  for (final (a, g) in _features(json))
    if (a['nom_complet'] case final String street)
      if (a['date_actif'] case final int start)
        Roadwork(
          street: street,
          shortName: _shortStreet(street),
          status: _status(_text(a['fermeture_etat'], or: 'travaux')),
          details: _text(a['remarque']),
          start: arcgisWallTime(start),
          end: a['date_fin'] is int ? arcgisWallTime(a['date_fin'] as int) : DateTime(2100),
          sector: a['secteur'] is String ? a['secteur'] as String : null,
          paths: readLonLatLists(g?['paths']),
        ),
];

Iterable<(Map<String, Object?>, Map<String, Object?>?)> _features(Map<String, Object?> json) sync* {
  final features = json['features'];
  if (features is! List) return;
  for (final f in features) {
    if (f is Map && f['attributes'] is Map) {
      final g = f['geometry'];
      yield (
        (f['attributes'] as Map).cast<String, Object?>(),
        g is Map ? g.cast<String, Object?>() : null,
      );
    }
  }
}

/// Une valeur codée peut arriver en nombre : on ne garde que le texte.
String _text(Object? raw, {String or = ''}) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : or;

WaterNoticeType _noticeType(Object? raw) {
  final s = _text(raw).toLowerCase();
  if (s.contains('bullition')) return WaterNoticeType.boil;
  if (s.contains('interruption')) return WaterNoticeType.interruption;
  if (s.contains('color')) return WaterNoticeType.discolored;
  return WaterNoticeType.other;
}

/// Les libellés de la Ville, raccourcis pour une tuile.
String _status(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('alternance')) return 'en alternance';
  if (s.contains('restriction')) return 'voies restreintes';
  if (s.contains('fermeture') || s.contains('fermée') || s.contains('fermee')) return 'fermée';
  if (s.contains('contresens')) return 'à contresens';
  return s;
}

String _shortStreet(String street) => street.replaceFirst(
  RegExp(
    r'^(Rue|Boulevard|Boul\.|Avenue|Chemin|Route|Rang|Montée)\s+(de la |des |du |de l’|de l\x27|de )?',
    caseSensitive: false,
  ),
  '',
);
