import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saguenay_assistant/assistant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'server_test.dart' show FakeClaude;

// Les vraies réponses enregistrées pour les tests du cœur.
List<int> fixture(String name) =>
    File('../packages/saguenay_core/test/fixtures/$name').readAsBytesSync();

/// Les sources publiques telles qu'elles ont répondu ; Environnement Canada,
/// Hydro-Québec et le ministère des Transports sont en panne, pour voir l'app
/// se débrouiller sans eux.
http.Client city({bool noAddress = false, void Function(Uri)? log}) => MockClient((r) async {
  final url = r.url;
  log?.call(url);
  String? name;
  if (url.path.contains('icherche')) {
    if (noAddress) return http.Response.bytes(utf8.encode('{"features": []}'), 200);
    name = 'icherche.json';
  } else if (url.path.contains('V_ATU_adresse_detaillee')) {
    name = 'adresses_ville.json';
  } else if (url.path.endsWith('/rues')) {
    name = 'collectes_rues.json';
  } else if (url.path.endsWith('/collectesinfos')) {
    name = 'collectes_infos.json';
  } else if (url.path.endsWith('/cedule')) {
    name = 'collectes_cedule_${Uri.splitQueryString(r.body)['horaire_id']}.json';
  } else if (url.path.contains('avis_aqueduc')) {
    name = 'avis_aqueduc.json';
  } else if (url.path.contains('etat_circulation')) {
    name = 'travaux.json';
  } else if (url.host == 'services3.arcgis.com') {
    name = 'qualite_air.json';
  } else if (url.path.contains('/apis/wss/')) {
    name = 'interdiction_feux.json';
  } else if (url.host == 'donnees.hydroquebec.com') {
    name = 'pointes_hydro.json';
  }
  if (name == null) return http.Response('panne', 503);
  return http.Response.bytes(fixture(name), 200);
});

void main() {
  final evening = DateTime(2026, 10, 26, 19, 30);

  group('la journée d’une adresse', () {
    test('une vraie adresse, sans téléphone intelligent', () async {
      final line = DayLine(client: city(), clock: () => evening);
      final text = await line.reply('201 racine est');
      expect(text, startsWith('201, rue Racine Est : '));
      expect(text.length, lessThanOrEqualTo(320));
      expect(text, isNot(contains('..')));
    });

    test('« aide » explique quoi écrire', () async {
      final line = DayLine(client: city(), clock: () => evening);
      expect(await line.reply('AIDE'), DayLine.help);
      expect(await line.reply('   '), DayLine.help);
    });

    test('une adresse introuvable le dit, sans planter', () async {
      final line = DayLine(client: city(noAddress: true), clock: () => evening);
      expect(await line.reply('123 rue Imaginaire'), DayLine.notFound);
    });

    test('les relevés de la ville servent dix minutes à tout le monde', () async {
      var calls = 0;
      final counting = city(
        log: (u) {
          if (u.path.contains('avis_aqueduc')) calls++;
        },
      );
      var now = evening;
      final line = DayLine(client: counting, clock: () => now);
      await line.reply('201 racine est');
      await line.reply('201 racine est');
      expect(calls, 1);
      now = now.add(DayLine.cityLifetime);
      await line.reply('201 racine est');
      expect(calls, 2);
    });
  });

  group('texto et téléphone (format Twilio)', () {
    Handler handler() {
      final claude = FakeClaude();
      return assistantHandler(
        claude: claude,
        press: PressDesk(claude, client: city()),
        dayLine: DayLine(client: city(), clock: () => evening),
      );
    }

    Future<(int, String, String?)> post(Handler h, String path, Map<String, String> form) async {
      final r = await h(
        Request(
          'POST',
          Uri.parse('http://localhost/$path'),
          body: Uri(queryParameters: form).query,
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );
      return (r.statusCode, await r.readAsString(), r.headers['content-type']);
    }

    test('un texto reçoit la journée de l’adresse', () async {
      final (status, body, type) = await post(handler(), 'sms', {
        'Body': '201 rue Racine Est',
        'From': '+15555550100',
      });
      expect(status, 200);
      expect(type, startsWith('text/xml'));
      expect(body, contains('<Message>201, rue Racine Est : '));
    });

    test('ce qu’on écrit ne peut pas injecter de balise', () {
      expect(
        TwiML.message('<Redirect>x</Redirect> & co'),
        contains('&lt;Redirect&gt;x&lt;/Redirect&gt; &amp; co'),
      );
    });

    test('au téléphone : on demande l’adresse, puis on lit la journée', () async {
      final h = handler();
      final (_, ask, _) = await post(h, 'voix', {'From': '+15555550101'});
      expect(ask, contains('<Gather input="speech" language="fr-CA"'));
      expect(ask, contains('action="voix/adresse"'));
      final (_, said, _) = await post(h, 'voix/adresse', {
        'SpeechResult': '201 rue Racine Est',
        'From': '+15555550101',
      });
      expect(said, contains('<Say language="fr-CA">201, rue Racine Est : '));
    });

    test('un même numéro est limité', () async {
      final claude = FakeClaude();
      final h = assistantHandler(
        claude: claude,
        press: PressDesk(claude, client: city()),
        dayLine: DayLine(client: city(), clock: () => evening),
        lineLimiter: RateLimiter(perClient: 1),
      );
      await post(h, 'sms', {'Body': 'aide', 'From': '+15555550102'});
      final (_, body, _) = await post(h, 'sms', {'Body': 'aide', 'From': '+15555550102'});
      expect(body, contains('Trop de demandes'));
      final (_, other, _) = await post(h, 'sms', {'Body': 'aide', 'From': '+15555550103'});
      expect(other, contains(DayLine.help.substring(0, 20)));
    });

    test('en JSON, pour un site ou un autre service', () async {
      final r = await handler()(
        Request('GET', Uri.parse('http://localhost/jour?adresse=201%20racine%20est')),
      );
      final json = jsonDecode(await r.readAsString()) as Map<String, Object?>;
      expect(json['answer'], startsWith('201, rue Racine Est'));
    });

    test('sans ligne configurée, ces chemins n’existent pas', () async {
      final claude = FakeClaude();
      final h = assistantHandler(
        claude: claude,
        press: PressDesk(claude, client: city()),
      );
      final r = await h(Request('POST', Uri.parse('http://localhost/sms'), body: 'Body=x'));
      expect(r.statusCode, 404);
    });
  });
}
