import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'address.dart';
import 'collection.dart';
import 'emergency.dart';
import 'parsers/arcgis.dart';
import 'parsers/city.dart';
import 'parsers/eccc.dart';
import 'parsers/gtfs.dart';
import 'parsers/gtfs_rt.dart';
import 'parsers/hydro.dart';
import 'parsers/msss.dart';
import 'parsers/mtmd.dart';
import 'power.dart';
import 'roads.dart';
import 'roadwork.dart';
import 'transit.dart';
import 'water.dart';
import 'weather.dart';

/// Télécharge [url] avec un délai et une taille maximale : un serveur lent ou
/// une réponse anormale ne doit ni bloquer l'app ni remplir la mémoire.
Future<Uint8List> download(
  http.Client client,
  Uri url, {
  int maxBytes = 2 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final response = await client.send(http.Request('GET', url)).timeout(timeout);
  if (response.statusCode != 200) {
    throw http.ClientException('Réponse ${response.statusCode}', url);
  }
  final declared = response.contentLength;
  if (declared != null && declared > maxBytes) {
    throw http.ClientException('Réponse trop volumineuse', url);
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.stream.timeout(timeout)) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) throw http.ClientException('Réponse trop volumineuse', url);
  }
  return bytes.takeBytes();
}

/// Va chercher le relevé horaire des urgences sur le site du ministère.
///
/// Le serveur n'envoie pas d'en-tête CORS : ça marche sur mobile, pas dans
/// un navigateur. Pour le web, il faudra passer par notre propre cache.
class MsssClient {
  MsssClient({http.Client? client}) : _client = client ?? http.Client();

  static final url = Uri.parse(
    'https://www.msss.gouv.qc.ca/professionnels/statistiques/documents/urgences/'
    'Releve_horaire_urgences_7jours_nbpers.csv',
  );

  final http.Client _client;

  Future<EmergencySnapshot> fetch() async =>
      parseMsssHourly(latin1.decode(await download(_client, url, maxBytes: 1024 * 1024)));

  void close() => _client.close();
}

/// Météo et alertes d'Environnement Canada (API GeoMet). L'API accepte les
/// requêtes des navigateurs : ça marche aussi sur le web.
class WeatherClient {
  WeatherClient({http.Client? client}) : _client = client ?? http.Client();

  /// Page « Saguenay » de la météo des villes.
  static final cityUrl = Uri.parse(
    'https://api.weather.gc.ca/collections/citypageweather-realtime/items/qc-166?f=json&lang=fr',
  );

  /// Centre de l'arrondissement de Chicoutimi, quand l'adresse n'a pas de coordonnées.
  static const saguenay = (lat: 48.4280, lon: -71.0680);

  final http.Client _client;

  static Uri alertsUrl(double lat, double lon) =>
      Uri.https('api.weather.gc.ca', '/collections/weather-alerts/items', {
        'f': 'json',
        'lang': 'fr',
        'limit': '50',
        'bbox': [
          lon - .02,
          lat - .02,
          lon + .02,
          lat + .02,
        ].map((v) => v.toStringAsFixed(4)).join(','),
      });

  Future<WeatherSnapshot> fetch({double? lat, double? lon, DateTime? now}) async {
    final (la, lo) = (lat ?? saguenay.lat, lon ?? saguenay.lon);
    final results = await Future.wait([
      download(_client, cityUrl),
      download(_client, alertsUrl(la, lo)),
    ]);
    final alerts = parseWeatherAlerts(_json(results[1]), now: now ?? DateTime.now());
    return parseCityWeather(_json(results[0]), alerts: alerts);
  }

  void close() => _client.close();
}

/// Pannes en cours et interruptions planifiées d'Hydro-Québec.
///
/// Deux temps : on lit le numéro de la dernière version, puis le fichier qui
/// porte ce numéro. Pas d'en-tête CORS ici non plus : mobile seulement.
class HydroClient {
  HydroClient({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://pannes.hydroquebec.com/pannes/donnees/v3_0/';

  final http.Client _client;

  Future<PowerSnapshot> fetch({DateTime? now}) async {
    final results = await Future.wait([
      _file('bisversion.json', 'bismarkers'),
      _file('aipversion.json', 'aipmarkers'),
    ]);
    return PowerSnapshot(
      takenAt: now ?? DateTime.now(),
      outages: [...parseOutages(results[0]), ...parsePlannedInterruptions(results[1])],
    );
  }

  Future<String> _file(String versionFile, String prefix) async {
    final raw = utf8.decode(
      await download(_client, Uri.parse('$_base$versionFile'), maxBytes: 1024),
    );
    final version = jsonDecode(raw);
    // Le numéro finit dans une adresse : on n'accepte que des chiffres.
    if (version is! String || !RegExp(r'^\d{8,20}$').hasMatch(version)) {
      throw const FormatException('Numéro de version inattendu');
    }
    return utf8.decode(await download(_client, Uri.parse('$_base$prefix$version.json')));
  }

  void close() => _client.close();
}

// Adresses ------------------------------------------------------------------------

/// Trouver une adresse de Saguenay : le géocodeur du Québec propose, la
/// couche d'adresses de la Ville confirme et donne le secteur.
class AddressClient {
  AddressClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri searchUrl(String query) =>
      Uri.https('geoegl.msp.gouv.qc.ca', '/apis/icherche/geocode', {
        'q': query.contains('saguenay') || query.contains('Saguenay') ? query : '$query, Saguenay',
        'type': 'adresses',
        'limit': '8',
        'geometry': '1',
      });

  static Uri cityUrl(double lat, double lon) => Uri.https(
    'cartographies.saguenay.ca',
    '/server/rest/services/Hosted/V_ATU_adresse_detaillee/FeatureServer/440/query',
    {
      'geometry': '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}',
      'geometryType': 'esriGeometryPoint',
      'inSR': '4326',
      'outSR': '4326',
      'distance': '60',
      'units': 'esriSRUnit_Meter',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': 'no_civique,rue,ville',
      'f': 'json',
    },
  );

  Future<List<AddressSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    return parseAddressSuggestions(
      _json(await download(_client, searchUrl(q), maxBytes: 256 * 1024)),
    );
  }

  /// L'adresse telle que la Ville la connaît, ou `null` si elle n'est pas à Saguenay.
  Future<ResolvedAddress?> resolve(AddressSuggestion s) async {
    final civic = civicOf(s.label);
    if (civic == null) return null;
    final json = _json(await download(_client, cityUrl(s.lat, s.lon), maxBytes: 256 * 1024));
    return parseCityAddress(json, civic: civic, lat: s.lat, lon: s.lon);
  }

  void close() => _client.close();
}

// Collectes ------------------------------------------------------------------------

/// L'horaire des collectes d'une adresse, lu comme le fait le formulaire
/// public du site de la Ville : trois petites requêtes, sans clé.
/// Une fois par semaine suffit ; on s'identifie poliment.
class CollectionClient {
  CollectionClient({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://ville.saguenay.ca/ajax/collectes/';
  final http.Client _client;

  Future<Object?> _post(String path, Map<String, String> body) async {
    final response = await _client
        .post(
          Uri.parse('$_base$path'),
          headers: {'X-Requested-With': 'XMLHttpRequest', 'User-Agent': 'saguenay-aujourdhui/0.2'},
          body: body,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException('Réponse ${response.statusCode}', Uri.parse('$_base$path'));
    }
    if (response.bodyBytes.length > 512 * 1024) {
      throw http.ClientException('Réponse trop volumineuse', Uri.parse('$_base$path'));
    }
    return decodeCityJson(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  Future<CollectionSchedule> schedule(ResolvedAddress address) async {
    final sector = sectorNumber(address.sector);
    if (sector == null) throw FormatException('Secteur inconnu : ${address.sector}');
    final building = parseCollectionBuilding(
      await _post('rues', {'no_civique': address.civic, 'no_ville': '$sector'}),
      street: address.street,
    );
    if (building == null) {
      throw const FormatException('Adresse absente du formulaire des collectes');
    }
    final types = parseCollectionTypes(
      await _post('collectesinfos', {'cle_batiment': '$building'}),
    );
    final next = <WasteStream, DateTime>{};
    for (final MapEntry(key: stream, value: id) in types.entries) {
      final day = parseNextCollection(await _post('cedule', {'horaire_id': '$id'}));
      if (day != null) next[stream] = day;
    }
    if (next.isEmpty) throw const FormatException('Aucune collecte pour cette adresse');
    return collectionFromNextDates(next);
  }

  void close() => _client.close();
}

// Aqueduc et travaux ---------------------------------------------------------------

/// Les couches publiques de la carte de la Ville, avec les zones et les tracés.
class CityLayersClient {
  CityLayersClient({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'cartographies.saguenay.ca';
  final http.Client _client;

  static Uri waterUrl() => Uri.https(
    _base,
    '/server/rest/services/COM_avis_aqueduc/avis_aqueduc/FeatureServer/0/query',
    {
      // Les avis des trente derniers jours suffisent : les plus vieux sont levés.
      'where': '1=1',
      'orderByFields': 'date_actif DESC',
      'resultRecordCount': '60',
      'outFields': 'avis_no,avis_desc,date_actif,date_fin,type_avis,status,deleted_at',
      'returnGeometry': 'true',
      'outSR': '4326',
      'geometryPrecision': '5',
      'f': 'json',
    },
  );

  static Uri roadworksUrl() => Uri.https(
    _base,
    '/server/rest/services/COM_etat_circulation/v_sag_etat_circulation_insgdb/FeatureServer/0/query',
    {
      'where': '1=1',
      'outFields': 'fermeture_etat,fermeture_type,nom_complet,secteur,date_actif,date_fin,remarque',
      'returnGeometry': 'true',
      'outSR': '4326',
      'geometryPrecision': '5',
      'f': 'json',
    },
  );

  Future<WaterSnapshot> water({DateTime? now}) async => WaterSnapshot(
    takenAt: now ?? DateTime.now(),
    notices: parseWaterNotices(_json(await download(_client, waterUrl()))),
  );

  Future<RoadworkSnapshot> roadworks({DateTime? now}) async => RoadworkSnapshot(
    takenAt: now ?? DateTime.now(),
    works: parseRoadworks(_json(await download(_client, roadworksUrl()))),
  );

  void close() => _client.close();
}

// Bus ------------------------------------------------------------------------------

/// Le flux de la STS : l'horaire complet (une fois par semaine) et le temps réel.
class TransitClient {
  TransitClient({http.Client? client}) : _client = client ?? http.Client();

  static final gtfsUrl = Uri.parse('https://saguenay.tmix.se/Tmix.Cap.TdExport.WebApi/gtfs/');
  static final tripUpdatesUrl = Uri.parse('https://saguenay.tmix.se/gtfs-realtime/tripupdates.pb');
  final http.Client _client;

  Future<Uint8List> gtfs() =>
      download(_client, gtfsUrl, maxBytes: 8 * 1024 * 1024, timeout: const Duration(seconds: 40));

  Future<TransitRealtime> realtime({DateTime? now}) async => parseTripUpdates(
    await download(_client, tripUpdatesUrl, maxBytes: 1024 * 1024),
    fallbackTime: now,
  );

  void close() => _client.close();
}

/// L'horaire des arrêts les plus proches, à partir du zip du flux. Lourd :
/// à faire tourner dans un isolat.
StopSchedule? stopScheduleFor(
  Uint8List gtfsZip,
  double lat,
  double lon, {
  required DateTime from,
  int days = 21,
}) {
  final feed = GtfsFeed.parse(gtfsZip);
  final stops = feed.nearestStops(lat, lon);
  if (stops.isEmpty) return null;
  return feed.schedule(stops, from: from, days: days);
}

// Routes ---------------------------------------------------------------------------

/// Conditions routières et caméras du ministère des Transports.
class RoadsClient {
  RoadsClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri layerUrl(String layer) => Uri.https('ws.mapserver.transports.gouv.qc.ca', '/swtq', {
    'service': 'wfs',
    'version': '2.0.0',
    'request': 'getfeature',
    'typename': layer,
    'outputformat': 'geojson',
    'srsName': 'EPSG:4326',
    // De Québec au Lac-Saint-Jean : toute la 175 y passe.
    'bbox': '46.8,-72.4,49.0,-70.3,urn:ogc:def:crs:EPSG::4326',
  });

  Future<RoadReport> fetch({DateTime? now}) async {
    final results = await Future.wait([
      download(_client, layerUrl('ms:conditions_routieres'), maxBytes: 4 * 1024 * 1024),
      download(_client, layerUrl('ms:infos_cameras'), maxBytes: 2 * 1024 * 1024),
    ]);
    return RoadReport(
      takenAt: now ?? DateTime.now(),
      segments: parseRoadConditions(_json(results[0])),
      cameras: parseCameras(_json(results[1])),
    );
  }

  void close() => _client.close();
}

Map<String, Object?> _json(Uint8List bytes) {
  final v = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  if (v is! Map) throw const FormatException('Objet JSON attendu');
  return v.cast<String, Object?>();
}
