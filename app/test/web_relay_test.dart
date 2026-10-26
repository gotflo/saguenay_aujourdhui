import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saguenay_aujourdhui/state/web_relay.dart';
import 'package:saguenay_core/saguenay_core.dart';

void main() {
  final base = Uri.parse('https://assistant.exemple.ca/');

  test('seules les sources qui bloquent les navigateurs passent par le relais', () {
    String? relayed(String url) => relayFor(Uri.parse(url), base)?.toString();

    expect(
      relayed('https://ville.saguenay.ca/ajax/collectes/rues'),
      'https://assistant.exemple.ca/relais/collectes/rues',
    );
    expect(
      relayFor(MsssClient.url, base).toString(),
      'https://assistant.exemple.ca/relais/urgences',
    );
    expect(
      relayed('https://pannes.hydroquebec.com/pannes/donnees/v3_0/bisversion.json'),
      'https://assistant.exemple.ca/relais/hydro/bisversion.json',
    );
    expect(relayFor(WeatherClient.cityUrl, base), isNull);
    expect(relayed('https://cartographies.saguenay.ca/server/rest/services/x/query'), isNull);
    expect(relayed('https://ville.saguenay.ca/autre-page'), isNull);
  });

  test('le formulaire des collectes suit, sans les en-têtes qu’un navigateur refuse', () async {
    late http.Request seen;
    final client = RelayClient(
      base,
      MockClient((r) async {
        seen = r;
        return http.Response('[]', 200);
      }),
    );
    await client.post(
      Uri.parse('https://ville.saguenay.ca/ajax/collectes/rues'),
      headers: {'X-Requested-With': 'XMLHttpRequest', 'User-Agent': 'saguenay-aujourdhui/0.2'},
      body: {'no_civique': '201', 'no_ville': '3'},
    );
    expect(seen.url, base.resolve('relais/collectes/rues'));
    expect(seen.method, 'POST');
    expect(seen.body, 'no_civique=201&no_ville=3');
    expect(seen.headers['content-type'], startsWith('application/x-www-form-urlencoded'));
    expect(seen.headers.keys, isNot(contains('x-requested-with')));
    expect(seen.headers.keys, isNot(contains('user-agent')));
  });

  test('le reste part directement', () async {
    late Uri seen;
    final client = RelayClient(
      base,
      MockClient((r) async {
        seen = r.url;
        return http.Response('{}', 200);
      }),
    );
    await client.get(WeatherClient.cityUrl);
    expect(seen, WeatherClient.cityUrl);
  });
}
