import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:saguenay_core/saguenay_core.dart';

import 'polite.dart';

/// Une réponse relayée : les octets et leur type, tels que reçus.
typedef Relayed = ({Uint8List body, String contentType});

class RelayRefused implements Exception {
  const RelayRefused(this.status);

  final int status;
}

/// Trois sources publiques n'envoient pas d'en-tête CORS : un navigateur
/// ne peut pas les lire. Pour la version web, le serveur les relaie telles
/// quelles, sur une liste fermée d'adresses, avec un cache court. Aucun
/// cookie ni jeton n'est transmis : seulement ce qu'un visiteur du site
/// enverrait.
class Relay {
  Relay({http.Client? client, DateTime Function()? clock})
    : _client = PoliteClient(client ?? http.Client()),
      _clock = clock ?? DateTime.now;

  static final emergencies = Uri.parse(
    'https://www.msss.gouv.qc.ca/professionnels/statistiques/documents/urgences/'
    'Releve_horaire_urgences_7jours_nbpers.csv',
  );
  static const hydroBase = 'https://pannes.hydroquebec.com/pannes/donnees/v3_0/';
  static const collectionsBase = 'https://ville.saguenay.ca/ajax/collectes/';

  static final _hydroFile = RegExp(
    r'^(bisversion|aipversion|bismarkers\d{8,20}|aipmarkers\d{8,20})\.json$',
  );
  static const _collectionSteps = {'rues', 'collectesinfos', 'cedule'};
  static final _formField = RegExp(r'^[a-z_]{1,20}=[0-9A-Za-z%+._-]{0,40}$');

  final http.Client _client;
  final DateTime Function() _clock;
  final _cache = <String, (DateTime, Relayed)>{};
  final _pending = <String, Future<Relayed>>{};

  /// Le relevé horaire des urgences du ministère.
  Future<Relayed> emergencyRoom() => _cached(
    'urgences',
    const Duration(minutes: 10),
    () => _get(emergencies, 1024 * 1024, 'text/csv; charset=iso-8859-1'),
  );

  /// Un fichier du site des pannes d'Hydro-Québec.
  Future<Relayed> hydro(String file) {
    if (!_hydroFile.hasMatch(file)) throw const RelayRefused(404);
    return _cached(
      'hydro:$file',
      const Duration(minutes: 2),
      () => _get(Uri.parse('$hydroBase$file'), 4 * 1024 * 1024, 'application/json'),
    );
  }

  /// Une étape du formulaire des collectes de la Ville. L'horaire d'une
  /// adresse change rarement : douze heures de cache.
  Future<Relayed> collections(String step, String form) {
    final fields = form.split('&');
    if (!_collectionSteps.contains(step) ||
        form.length > 200 ||
        fields.length > 4 ||
        !fields.every(_formField.hasMatch)) {
      throw const RelayRefused(400);
    }
    return _cached('collectes:$step:$form', const Duration(hours: 12), () async {
      final response = await _client
          .post(
            Uri.parse('$collectionsBase$step'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'X-Requested-With': 'XMLHttpRequest',
            },
            body: form,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.length > 512 * 1024) {
        throw http.ClientException('Réponse ${response.statusCode}');
      }
      return (
        body: response.bodyBytes,
        contentType: response.headers['content-type'] ?? 'application/json',
      );
    });
  }

  Future<Relayed> _get(Uri url, int maxBytes, String contentType) async =>
      (body: await download(_client, url, maxBytes: maxBytes), contentType: contentType);

  Future<Relayed> _cached(String key, Duration lifetime, Future<Relayed> Function() read) {
    final hit = _cache[key];
    if (hit != null && _clock().difference(hit.$1) < lifetime) return Future.value(hit.$2);
    return _pending[key] ??= read()
        .then((value) {
          _cache[key] = (_clock(), value);
          if (_cache.length > 5000) _cache.clear();
          return value;
        })
        .whenComplete(() {
          // Sans accolades, whenComplete attendrait le futur retiré, c'est-à-dire lui-même.
          _pending.remove(key);
        });
  }

  void close() => _client.close();
}
