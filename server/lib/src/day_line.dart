import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:saguenay_core/saguenay_core.dart';

import 'polite.dart';

/// La journée d'une adresse, sans téléphone intelligent : on texte son
/// adresse (ou on la dit au téléphone) et on reçoit quelques phrases. Le
/// serveur ne garde ni le numéro ni l'adresse : seulement les relevés publics
/// de la ville, quelques minutes, et l'horaire de collecte d'une adresse.
class DayLine {
  DayLine({http.Client? client, DateTime Function()? clock})
    : _client = PoliteClient(client ?? http.Client()),
      _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;

  static const cityLifetime = Duration(minutes: 10);
  static const scheduleLifetime = Duration(hours: 12);

  static const help =
      'Écris ton adresse à Saguenay, par exemple : 201 rue Racine Est. '
      'Tu recevras ce qui la concerne aujourd’hui : eau, stationnement, collecte, pannes.';

  static const notFound =
      'Je ne trouve pas cette adresse à Saguenay. Écris le numéro et la rue, '
      'par exemple : 201 rue Racine Est.';

  ({DateTime at, CityData city})? _city;
  Future<CityData>? _cityPending;
  final _schedules = <String, ({DateTime at, CollectionSchedule schedule})>{};

  /// Le texte à renvoyer pour ce qu'on a reçu : une adresse, ou « aide ».
  Future<String> reply(String message) async {
    final text = message.trim();
    if (text.isEmpty || RegExp(r'^(aide|help|info|\?)$', caseSensitive: false).hasMatch(text)) {
      return help;
    }
    final address = await _resolve(text.length > 120 ? text.substring(0, 120) : text);
    if (address == null) return notFound;
    final city = await _cityData();
    final place = livePlace(
      address,
      collection: await _schedule(address),
      water: _water,
      roadworks: _works,
    );
    return DaySummary.text(place, city, _clock());
  }

  Future<ResolvedAddress?> _resolve(String text) async {
    final addresses = AddressClient(client: _client);
    final found = await addresses.search(text);
    for (final s in found.take(2)) {
      final a = await addresses.resolve(s);
      if (a != null) return a;
    }
    return null;
  }

  Future<CollectionSchedule?> _schedule(ResolvedAddress a) async {
    final known = _schedules[a.id];
    if (known != null && _clock().difference(known.at) < scheduleLifetime) return known.schedule;
    try {
      final s = await CollectionClient(client: _client).schedule(a);
      if (_schedules.length > 2000) _schedules.clear();
      _schedules[a.id] = (at: _clock(), schedule: s);
      return s;
    } on Exception {
      return known?.schedule;
    }
  }

  WaterSnapshot? _water;
  RoadworkSnapshot? _works;

  Future<CityData> _cityData() {
    final known = _city;
    if (known != null && _clock().difference(known.at) < cityLifetime) {
      return Future.value(known.city);
    }
    return _cityPending ??= _loadCity().whenComplete(() {
      _cityPending = null;
    });
  }

  Future<CityData> _loadCity() async {
    final now = _clock();
    Future<T?> attempt<T>(Future<T> Function() read) async {
      try {
        return await read();
      } on Exception {
        return null;
      }
    }

    final layers = CityLayersClient(client: _client);
    final env = EnvironmentClient(client: _client);
    final results = await Future.wait<Object?>([
      attempt(() => layers.water(now: now)),
      attempt(() => layers.roadworks(now: now)),
      attempt(() => WeatherClient(client: _client).fetch(now: now)),
      attempt(() => HydroClient(client: _client).fetch(now: now)),
      attempt(() => RoadsClient(client: _client).fetch(now: now)),
      attempt(() => env.air(now: now)),
      attempt(() => env.fireBans(now: now)),
      attempt(() => env.peaks(now: now)),
    ]);
    // Un relevé raté garde le précédent plutôt que de laisser un trou.
    final previous = _city?.city;
    final water = results[0] as WaterSnapshot?;
    _water = water ?? _water;
    _works = results[1] as RoadworkSnapshot? ?? _works;
    final city = CityData(
      waterNotices: _water?.notices ?? const [],
      waterKnownUntil: _water?.knownUntil,
      weather: results[2] as WeatherSnapshot? ?? previous?.weather,
      power: results[3] as PowerSnapshot? ?? previous?.power,
      roads: results[4] as RoadReport? ?? previous?.roads,
      air: results[5] as AirSnapshot? ?? previous?.air,
      fireBans: results[6] as FireBanSnapshot? ?? previous?.fireBans,
      peaks: results[7] as PeakSnapshot? ?? previous?.peaks,
    );
    _city = (at: now, city: city);
    return city;
  }

  void close() => _client.close();
}

/// Les réponses au format TwiML de Twilio (texto et voix). Le texte est
/// échappé : une adresse tapée ne peut pas injecter de balise.
abstract final class TwiML {
  static String message(String text) =>
      '<?xml version="1.0" encoding="UTF-8"?><Response><Message>${_escape(text)}</Message></Response>';

  static String ask(String actionPath) =>
      '<?xml version="1.0" encoding="UTF-8"?><Response>'
      '<Gather input="speech" language="fr-CA" speechTimeout="auto" action="${_escape(actionPath)}" method="POST">'
      '<Say language="fr-CA">Bonjour. Dites votre adresse à Saguenay, par exemple : deux cent un, rue Racine Est.</Say>'
      '</Gather>'
      '<Say language="fr-CA">Je n’ai rien entendu. Au revoir.</Say>'
      '</Response>';

  static String say(String text) =>
      '<?xml version="1.0" encoding="UTF-8"?><Response><Say language="fr-CA">${_escape(text)}</Say></Response>';

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
