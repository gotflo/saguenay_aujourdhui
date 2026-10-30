/// Le serveur de l'assistant en ligne : il garde la clé d'API de Claude et
/// n'expose que quelques demandes précises, chacune bornée. Il relaie aussi,
/// pour la version web, trois sources publiques qui bloquent les navigateurs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'src/claude.dart';
import 'src/day_line.dart';
import 'src/limits.dart';
import 'src/press.dart';
import 'src/prompts.dart';
import 'src/relay.dart';

export 'src/claude.dart';
export 'src/day_line.dart';
export 'src/limits.dart';
export 'src/polite.dart';
export 'src/press.dart';
export 'src/prompts.dart';
export 'src/relay.dart';

const maxQuestion = 500;
const maxText = 4000;
const maxImageBytes = 5 * 1024 * 1024;

class _Refused implements Exception {
  const _Refused(this.status, this.message);

  final int status;
  final String message;
}

/// `allowedOrigins` vide : n'importe quel site peut appeler (aucun cookie,
/// aucune donnée de compte ne transite). `trustProxy` : lire l'adresse de
/// l'appareil dans `X-Forwarded-For`, derrière un proxy de confiance.
Handler assistantHandler({
  required Claude claude,
  required PressDesk press,
  Relay? relay,
  DayLine? dayLine,
  RateLimiter? limiter,
  RateLimiter? relayLimiter,
  RateLimiter? lineLimiter,
  Set<String> allowedOrigins = const {},
  bool trustProxy = false,
}) {
  final limits = limiter ?? RateLimiter();
  final relayLimits = relayLimiter ?? RateLimiter(perClient: 120, perDay: 100000);
  final lineLimits = lineLimiter ?? RateLimiter(perClient: 10, perDay: 5000);

  return (Request request) async {
    final cors = _cors(request.headers['origin'], allowedOrigins);
    Response respond(
      int status,
      Map<String, Object?> body, [
      Map<String, String> extra = const {},
    ]) => Response(
      status,
      body: jsonEncode(body),
      headers: {
        ...cors,
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        ...extra,
      },
    );

    if (request.method == 'OPTIONS') return Response(204, headers: cors);
    final path = request.url.path;
    try {
      if (request.url.pathSegments case ['relais', ...final rest] when relay != null) {
        if (relayLimits.check(_clientOf(request, trustProxy)) case final wait?) {
          return respond(
            429,
            {'erreur': 'Trop de demandes.'},
            {'retry-after': '${wait.inSeconds + 1}'},
          );
        }
        final Relayed relayed;
        switch ((request.method, rest)) {
          case ('GET', ['urgences']):
            relayed = await relay.emergencyRoom();
          case ('GET', ['hydro', final file]):
            relayed = await relay.hydro(file);
          case ('POST', ['collectes', final step]):
            relayed = await relay.collections(step, utf8.decode(await _readBytes(request, 1024)));
          default:
            return respond(404, {'erreur': 'Introuvable'});
        }
        return Response.ok(
          relayed.body,
          headers: {...cors, 'content-type': relayed.contentType, 'cache-control': 'no-store'},
        );
      }
      if (dayLine != null && const {'jour', 'sms', 'voix', 'voix/adresse'}.contains(path)) {
        return await _line(request, path, dayLine, lineLimits, trustProxy, respond, cors);
      }
      switch ((request.method, path)) {
        case ('GET', 'sante'):
          return respond(200, {'ok': true});
        case ('GET', 'communiques'):
          return respond(200, {'communiques': await press.latest()});
        case ('POST', 'question' || 'tri' || 'expliquer'):
          if (limits.check(_clientOf(request, trustProxy)) case final wait?) {
            return respond(
              429,
              {'erreur': 'Trop de demandes. Réessaie un peu plus tard.'},
              {'retry-after': '${wait.inSeconds + 1}'},
            );
          }
          final body = await _readJson(request, path == 'tri' ? 8 * 1024 * 1024 : 32 * 1024);
          final answer = await switch (path) {
            'question' => claude.reply(
              system: questionPrompt,
              content: questionContent(body, press: press.known()),
            ),
            'tri' => claude.reply(system: sortingPrompt, content: photoContent(body)),
            _ => claude.reply(system: plainPrompt, content: plainContent(body)),
          };
          return respond(200, {'answer': answer});
        default:
          return respond(404, {'erreur': 'Introuvable'});
      }
    } on _Refused catch (e) {
      return respond(e.status, {'erreur': e.message});
    } on RelayRefused catch (e) {
      return respond(e.status, {'erreur': 'Demande refusée'});
    } on ClaudeDeclined {
      return respond(200, {'answer': declinedAnswer});
    } on ClaudeUnavailable {
      return respond(503, {'erreur': 'L’assistant ne répond pas pour l’instant.'});
    } on Exception {
      // La page des communiqués ne répond pas et rien n'est en mémoire.
      return respond(503, {'erreur': 'Le service ne répond pas pour l’instant.'});
    }
  };
}

/// La journée d'une adresse : en JSON (`GET /jour?adresse=`), par texto
/// (`POST /sms`) ou au téléphone (`POST /voix`, puis `/voix/adresse`), au
/// format de Twilio. On limite par numéro quand il y en a un, sans le garder.
Future<Response> _line(
  Request request,
  String path,
  DayLine line,
  RateLimiter limits,
  bool trustProxy,
  Response Function(int, Map<String, Object?>, [Map<String, String>]) respond,
  Map<String, String> cors,
) async {
  Response xml(String body) => Response.ok(
    body,
    headers: {...cors, 'content-type': 'text/xml; charset=utf-8', 'cache-control': 'no-store'},
  );
  final form = request.method == 'POST'
      ? Uri.splitQueryString(utf8.decode(await _readBytes(request, 8 * 1024), allowMalformed: true))
      : const <String, String>{};
  final from = form['From'];
  final who = from == null || from.isEmpty
      ? _clientOf(request, trustProxy)
      : 'tel:${from.hashCode}';
  if (limits.check(who) case final wait?) {
    const busy = 'Trop de demandes. Réessaie dans quelques minutes.';
    return switch (path) {
      'sms' => xml(TwiML.message(busy)),
      'voix' || 'voix/adresse' => xml(TwiML.say(busy)),
      _ => respond(429, {'erreur': busy}, {'retry-after': '${wait.inSeconds + 1}'}),
    };
  }
  switch ((request.method, path)) {
    case ('GET', 'jour'):
      final address = request.url.queryParameters['adresse'] ?? '';
      if (address.trim().isEmpty) throw const _Refused(400, 'Paramètre « adresse » attendu');
      return respond(200, {'answer': await line.reply(address)});
    case ('POST', 'sms'):
      return xml(TwiML.message(await line.reply(form['Body'] ?? '')));
    case ('POST', 'voix'):
      return xml(TwiML.ask('voix/adresse'));
    case ('POST', 'voix/adresse'):
      final heard = form['SpeechResult'] ?? '';
      return xml(TwiML.say(heard.trim().isEmpty ? DayLine.help : await line.reply(heard)));
    default:
      return respond(404, {'erreur': 'Introuvable'});
  }
}

Map<String, String> _cors(String? origin, Set<String> allowed) => {
  'access-control-allow-origin': allowed.isEmpty
      ? '*'
      : (origin != null && allowed.contains(origin) ? origin : allowed.first),
  if (allowed.isNotEmpty) 'vary': 'Origin',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
  'access-control-max-age': '600',
};

String _clientOf(Request request, bool trustProxy) {
  final forwarded = request.headers['x-forwarded-for'];
  if (trustProxy && forwarded != null && forwarded.trim().isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  final info = request.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'inconnu';
}

Future<Uint8List> _readBytes(Request request, int maxBytes) async {
  if ((request.contentLength ?? 0) > maxBytes) throw const _Refused(413, 'Demande trop lourde');
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) throw const _Refused(413, 'Demande trop lourde');
  }
  return bytes.takeBytes();
}

Future<Map<String, Object?>> _readJson(Request request, int maxBytes) async {
  final bytes = await _readBytes(request, maxBytes);
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is Map<String, Object?>) return json;
  } on FormatException {
    // Traité plus bas.
  }
  throw const _Refused(400, 'JSON attendu');
}

String _text(Map<String, Object?> body, String key, int max) {
  final value = body[key];
  if (value is! String || value.trim().isEmpty) throw _Refused(400, 'Champ « $key » attendu');
  if (value.length > max) throw _Refused(413, 'Champ « $key » trop long');
  return value.trim();
}

const _contextFields = {
  'secteur': 'Secteur',
  'moment': 'Moment',
  'carte': 'Carte du haut',
  'tuiles': 'Tuiles',
  'semaine': 'La semaine',
  'eau': 'Eau',
  'stationnement': 'Stationnement',
  'collectes': 'Collectes',
  'bus': 'Bus',
  'meteo': 'Météo',
  'previsions': 'Prévisions',
  'pannes': 'Pannes',
  'routes': 'Routes',
  'travaux': 'Travaux',
  'urgences': 'Urgences',
  'air': 'Qualité de l’air',
  'feux': 'Feux à ciel ouvert',
  'pointes': 'Pointes d’Hydro-Québec',
};

const maxExchanges = 4;

String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

/// Ce que dit la personne ou une source ne peut pas fermer une balise.
String _inert(String s) => s.replaceAll('<', '‹').replaceAll('>', '›');

/// Le contexte envoyé par l'app, réduit aux champs connus et borné.
String contextText(Object? raw) {
  if (raw is! Map) return 'Aucun contexte.';
  final lines = <String>[
    for (final MapEntry(:key, value: label) in _contextFields.entries)
      if (raw[key] case final String v when v.trim().isNotEmpty)
        '$label : ${_inert(_clip(v.trim(), 400))}'
      else if (raw[key] case final List<Object?> items when items.isNotEmpty)
        '$label : ${[for (final i in items.take(12))
          if (i is String) _inert(_clip(i, 200))].join(' ; ')}',
  ];
  return lines.isEmpty ? 'Aucun contexte.' : lines.join('\n');
}

/// Les questions d'avant, bornées, pour comprendre une suite comme « Et demain ? ».
String exchangesText(Object? raw) => [
  if (raw is List)
    for (final e in raw.skip(raw.length > maxExchanges ? raw.length - maxExchanges : 0))
      if (e is Map && e['question'] is String && e['reponse'] is String)
        'Question : ${_inert(_clip(e['question'] as String, maxQuestion))}\n'
            'Réponse : ${_inert(_clip(e['reponse'] as String, 500))}',
].join('\n');

List<Map<String, Object?>> questionContent(
  Map<String, Object?> body, {
  List<String> press = const [],
}) {
  final question = _inert(_text(body, 'question', maxQuestion));
  final exchanges = exchangesText(body['historique']);
  return [
    {
      'type': 'text',
      'text': [
        '<contexte>\n${contextText(body['context'])}\n</contexte>',
        if (press.isNotEmpty) '<communiques>\n${_inert(press.join('\n'))}\n</communiques>',
        if (exchanges.isNotEmpty) '<echanges>\n$exchanges\n</echanges>',
        '<question>\n$question\n</question>',
      ].join('\n\n'),
    },
  ];
}

List<Map<String, Object?>> plainContent(Map<String, Object?> body) => [
  {'type': 'text', 'text': '<texte>\n${_inert(_text(body, 'texte', maxText))}\n</texte>'},
];

List<Map<String, Object?>> photoContent(Map<String, Object?> body) {
  final Uint8List image;
  try {
    image = base64Decode(_text(body, 'image', maxImageBytes * 4 ~/ 3 + 4));
  } on FormatException {
    throw const _Refused(400, 'Image illisible');
  }
  if (image.length > maxImageBytes) throw const _Refused(413, 'Image trop lourde');
  final type = imageType(image);
  if (type == null) throw const _Refused(415, 'Photo JPEG, PNG ou WebP attendue');
  return [
    {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': type, 'data': base64Encode(image)},
    },
    {'type': 'text', 'text': 'Ça va où ?'},
  ];
}

/// Le type d'image d'après ses premiers octets, pas d'après ce que dit
/// l'appelant.
String? imageType(Uint8List b) {
  bool at(int offset, List<int> sig) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'image/png';
  if (at(0, ascii.encode('RIFF')) && at(8, ascii.encode('WEBP'))) return 'image/webp';
  return null;
}
