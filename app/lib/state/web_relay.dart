import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/assistant/remote_assistant.dart';

/// Dans un navigateur, notre serveur relaie les sources publiques qui
/// n'envoient pas d'en-tête CORS. `null` sur le téléphone, ou sans serveur.
final Uri? webRelay = kIsWeb ? assistantBase : null;

/// L'adresse du relais pour une requête, ou `null` si elle part telle quelle.
Uri? relayFor(Uri url, Uri base) {
  if (url.host == 'ville.saguenay.ca' && url.path.startsWith('/ajax/collectes/')) {
    return base.resolve('relais/collectes/${url.pathSegments.last}');
  }
  if (url.host == 'www.msss.gouv.qc.ca') return base.resolve('relais/urgences');
  if (url.host == 'pannes.hydroquebec.com') {
    return base.resolve('relais/hydro/${url.pathSegments.last}');
  }
  return null;
}

/// Envoie au relais ce qui doit y passer, le reste directement. Seul le type
/// du contenu suit : un navigateur refuserait les autres en-têtes.
class RelayClient extends http.BaseClient {
  RelayClient(this.base, [http.Client? inner]) : _inner = inner ?? http.Client();

  final Uri base;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final target = relayFor(request.url, base);
    if (target == null) return _inner.send(request);
    final copy = http.Request(request.method, target);
    if (request.headers['content-type'] case final type?) copy.headers['content-type'] = type;
    copy.bodyBytes = await request.finalize().toBytes();
    return _inner.send(copy);
  }

  @override
  void close() => _inner.close();
}

/// Le client HTTP des sources publiques : direct, ou par le relais.
http.Client sourceClient() {
  final relay = webRelay;
  return relay == null ? http.Client() : RelayClient(relay);
}
