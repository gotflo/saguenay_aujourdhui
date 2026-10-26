import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

const _csv =
    'Nom_installation,No_permis_installation,Nombre_de_civieres_fonctionnelles,'
    'Nombre_de_civieres_occupees,Nombre_total_de_patients_presents_a_lurgence,'
    'Nombre_total_de_patients_en_attente_de_PEC,Mise_a_jour\n'
    'HÔPITAL DE CHICOUTIMI,51218394,41,34,40,2,2026-10-25T9:45\n';

void main() {
  test('décode le fichier en Latin-1', () async {
    final client = MsssClient(
      client: MockClient((request) async {
        expect(request.url, MsssClient.url);
        return http.Response.bytes(latin1.encode(_csv), 200);
      }),
    );
    final snapshot = await client.fetch();
    expect(snapshot.takenAt, DateTime(2026, 10, 25, 9, 45));
    expect(snapshot.rooms.single.hospital, 'Chicoutimi');
  });

  test('signale une réponse en erreur', () {
    final client = MsssClient(client: MockClient((_) async => http.Response('', 503)));
    expect(client.fetch(), throwsA(isA<http.ClientException>()));
  });
}
