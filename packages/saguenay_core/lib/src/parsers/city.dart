import 'dart:convert';

import '../address.dart';
import '../calendar.dart';
import '../collection.dart';
import '../geo.dart';

/// Géocodeur du gouvernement du Québec (`geoegl.msp.gouv.qc.ca/apis/icherche/geocode`).
/// On ne garde que les adresses de Saguenay.
List<AddressSuggestion> parseAddressSuggestions(Map<String, Object?> json) => [
  for (final f in (json['features'] as List?) ?? const [])
    if (f is Map)
      if ((f['properties'] as Map?)?['nom'] case final String label
          when label.contains(', Saguenay'))
        if (f['geometry'] case {'coordinates': [final num lon, final num lat]})
          AddressSuggestion(label: label, lat: lat.toDouble(), lon: lon.toDouble()),
];

/// Couche d'adresses de la Ville (`Hosted/V_ATU_adresse_detaillee/FeatureServer/440`),
/// interrogée autour du point donné par le géocodeur. On garde le bâtiment
/// au bon numéro, sinon le plus proche.
ResolvedAddress? parseCityAddress(
  Map<String, Object?> json, {
  required String civic,
  required double lat,
  required double lon,
}) {
  ResolvedAddress? best;
  var bestScore = double.infinity;
  for (final f in (json['features'] as List?) ?? const []) {
    if (f is! Map) continue;
    final a = (f['attributes'] as Map?)?.cast<String, Object?>();
    final g = f['geometry'];
    if (a == null || g is! Map || g['x'] is! num || g['y'] is! num) continue;
    final no = '${a['no_civique'] ?? ''}'.trim();
    final street = a['rue'], sector = a['ville'];
    if (no.isEmpty || street is! String || sector is! String) continue;
    final x = (g['x'] as num).toDouble(), y = (g['y'] as num).toDouble();
    final d =
        distanceToPaths(
          [
            [(x, y)],
          ],
          lat,
          lon,
        ) +
        (no == civic ? 0 : 1000);
    if (d < bestScore) {
      bestScore = d;
      best = ResolvedAddress(
        civic: no,
        street: street.trim(),
        sector: sector.trim(),
        lat: y,
        lon: x,
      );
    }
  }
  return best;
}

/// Le numéro civique au début d'une adresse : « 201 rue Racine Est » → « 201 ».
String? civicOf(String label) => RegExp(r'^\s*(\d+[A-Za-z]?)').firstMatch(label)?.group(1);

/// Le site de la Ville précède parfois son JSON de lignes vides.
Object? decodeCityJson(String body) => jsonDecode(body.trim());

/// Formulaire des collectes, étape 1 (`ajax/collectes/rues`) : les rues qui
/// ont ce numéro civique dans ce secteur. Rend l'identifiant du bâtiment.
int? parseCollectionBuilding(Object? rues, {required String street}) {
  if (rues is! List) return null;
  final key = streetKey(street);
  for (final r in rues) {
    if (r is Map && r['rue'] is String && streetKey(r['rue'] as String) == key && r['id'] is int) {
      return r['id'] as int;
    }
  }
  return null;
}

/// Étape 2 (`ajax/collectes/collectesinfos`) : un horaire par type de collecte.
Map<WasteStream, int> parseCollectionTypes(Object? infos) {
  final out = <WasteStream, int>{};
  if (infos is! List) return out;
  for (final i in infos) {
    if (i is! Map || i['horaire_id'] is! int) continue;
    final stream = switch ('${i['acronyme']}'.toUpperCase()) {
      'ORD' => WasteStream.garbage,
      'REC' => WasteStream.recycling,
      'COM' => WasteStream.compost,
      _ => null,
    };
    if (stream != null) out[stream] = i['horaire_id'] as int;
  }
  return out;
}

/// Étape 3 (`ajax/collectes/cedule`) : la prochaine date de collecte.
/// Le serveur la donne à minuit, heure locale, exprimée en UTC.
DateTime? parseNextCollection(Object? cedule) {
  if (cedule is! Map || cedule['date_collecte'] is! String) return null;
  final d = DateTime.tryParse(cedule['date_collecte'] as String)?.toLocal();
  return d == null ? null : startOfDay(d);
}

/// L'horaire d'une adresse à partir des prochaines dates : chaque collecte
/// revient aux deux semaines le même jour, le compost chaque semaine l'été.
/// Relu chaque semaine, il reprend de lui-même les décalages des jours fériés.
CollectionSchedule collectionFromNextDates(Map<WasteStream, DateTime> next) {
  if (next.isEmpty) return const CollectionSchedule({});
  final last = next.values.reduce((a, b) => a.isAfter(b) ? a : b);
  return CollectionSchedule({
    for (final MapEntry(key: stream, value: day) in next.entries)
      stream: CollectionRule(
        weekday: day.weekday,
        anchor: day,
        weeklyInSummer: stream == WasteStream.compost,
      ),
  }, publishedThrough: DateTime(last.year, 12, 31));
}
