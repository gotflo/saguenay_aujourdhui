import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saguenay_assistant/assistant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'server_test.dart' show FakeClaude;

void main() {
  late List<http.Request> upstream;
  late Handler handler;

  Handler build(http.Client client) {
    final claude = FakeClaude();
    return assistantHandler(
      claude: claude,
      press: PressDesk(claude, client: client),
      relay: Relay(client: client),
    );
  }

  setUp(() {
    upstream = [];
    handler = build(
      MockClient((r) async {
        upstream.add(r);
        if (r.url.host == 'www.msss.gouv.qc.ca') {
          return http.Response.bytes(latin1.encode('Région;Hôpital\n'), 200);
        }
        if (r.url.host == 'pannes.hydroquebec.com') return http.Response('"20261025220000"', 200);
        return http.Response.bytes(utf8.encode('   [{"id":"292","rue":"Racine Est"}]'), 200);
      }),
    );
  });

  Future<Response> send(String method, String path, {String? body}) async => handler(
    Request(
      method,
      Uri.parse('http://localhost/$path'),
      body: body,
      headers: {if (body != null) 'content-type': 'application/x-www-form-urlencoded'},
    ),
  );

  test('les urgences, octet pour octet, avec un cache de dix minutes', () async {
    final r = await send('GET', 'relais/urgences');
    expect(r.statusCode, 200);
    expect(latin1.decode(await r.read().expand((c) => c).toList()), 'Région;Hôpital\n');
    expect(r.headers['access-control-allow-origin'], '*');
    await send('GET', 'relais/urgences');
    expect(upstream, hasLength(1));
    expect(upstream.single.headers['user-agent'], PoliteClient.agent);
  });

  test('Hydro-Québec : seulement ses fichiers de pannes', () async {
    expect((await send('GET', 'relais/hydro/bisversion.json')).statusCode, 200);
    expect((await send('GET', 'relais/hydro/aipmarkers20261025220000.json')).statusCode, 200);
    expect((await send('GET', 'relais/hydro/index.html')).statusCode, 404);
    expect((await send('GET', 'relais/hydro/bismarkers1.json')).statusCode, 404);
    expect(upstream.map((r) => r.url.path), [
      '/pannes/donnees/v3_0/bisversion.json',
      '/pannes/donnees/v3_0/aipmarkers20261025220000.json',
    ]);
  });

  test('les collectes : le formulaire public, comme un navigateur', () async {
    final r = await send('POST', 'relais/collectes/rues', body: 'no_civique=201&no_ville=3');
    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('"292"'));
    final sent = upstream.single;
    expect(sent.url.toString(), 'https://ville.saguenay.ca/ajax/collectes/rues');
    expect(sent.body, 'no_civique=201&no_ville=3');
    expect(sent.headers['x-requested-with'], 'XMLHttpRequest');
    expect(sent.headers.keys, isNot(contains('cookie')));
    expect(sent.headers.keys, isNot(contains('authorization')));
  });

  test('les collectes : rien d’autre ne passe', () async {
    expect((await send('POST', 'relais/collectes/admin', body: 'a=1')).statusCode, 400);
    expect((await send('POST', 'relais/collectes/rues', body: 'a=1;b')).statusCode, 400);
    expect(
      (await send('POST', 'relais/collectes/rues', body: 'a=1&b=2&c=3&d=4&e=5')).statusCode,
      400,
    );
    expect((await send('GET', 'relais/collectes/rues')).statusCode, 404);
    expect((await send('POST', 'relais/collectes/rues', body: 'a=${'1' * 2000}')).statusCode, 413);
    expect(upstream, isEmpty);
  });

  test('la source ne répond pas : 503', () async {
    final h = build(MockClient((_) async => http.Response('', 500)));
    final r = await h(Request('GET', Uri.parse('http://localhost/relais/urgences')));
    expect(r.statusCode, 503);
  });

  test('sans relais configuré, rien n’est relayé', () async {
    final claude = FakeClaude();
    final h = assistantHandler(claude: claude, press: PressDesk(claude));
    final r = await h(Request('GET', Uri.parse('http://localhost/relais/urgences')));
    expect(r.statusCode, 404);
  });

  test('sans clé d’API, l’assistant dit qu’il n’est pas là', () async {
    final h = assistantHandler(claude: const NoClaude(), press: PressDesk(const NoClaude()));
    final r = await h(
      Request('POST', Uri.parse('http://localhost/question'), body: '{"question":"Salut"}'),
    );
    expect(r.statusCode, 503);
  });
}
