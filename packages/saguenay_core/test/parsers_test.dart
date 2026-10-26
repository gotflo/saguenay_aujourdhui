import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

// Extrait du relevé du 25 octobre 2026, 6 h 45, en-têtes d'origine compris.
const _csv = '''
RSS,Region,Nom_etablissement,Nom_installation,No_permis_installation,Nombre_de_civieres_fonctionnelles,Nombre_de_civieres_occupees\t\t\t\t      ,Nombre_de_patients_sur_civiere_plus_de_24_heures,Nombre_de_patients_sur_civiere_plus_de_48_heures,Nombre_total_de_patients_presents_a_lurgence\t\t\t\t      ,Nombre_total_de_patients_en_attente_de_PEC,DMS_sur_civiere,DMS_ambulatoire,DMS_sur_civiere_horaire,DMS_ambulatoire_horaire\t\t\t\t      ,Heure_de_l'extraction_(image), Mise_a_jour
02,Saguenay-Lac-Saint-Jean,Total régional,Total régional, ,104,72,2,0,100,20,11.6,4.17,11:36,4:10,6:00:00,2026-10-25T6:45
02,Saguenay-Lac-Saint-Jean,SANTÉ QUÉBEC SAGUENAY - LAC-SAINT-JEAN - UNIVERSITAIRE,HÔPITAL DE CHICOUTIMI,51218394,41,34,0,0,40,2,11.78,5.2,11:46,5:12,6:00:00,2026-10-25T6:45
02,Saguenay-Lac-Saint-Jean,SANTÉ QUÉBEC SAGUENAY - LAC-SAINT-JEAN - UNIVERSITAIRE,HÔPITAL D'ALMA,51219400,17,8,0,0,17,6,6.28,3.03,6:16,3:01,6:00:00,2026-10-25T6:45
02,Saguenay-Lac-Saint-Jean,SANTÉ QUÉBEC SAGUENAY - LAC-SAINT-JEAN - UNIVERSITAIRE,HÔPITAL DE LA BAIE,51221364,7,4,1,0,6,2,10.75,4.18,10:45,4:10,6:00:00,2026-10-25T6:45
02,Saguenay-Lac-Saint-Jean,SANTÉ QUÉBEC SAGUENAY - LAC-SAINT-JEAN - UNIVERSITAIRE,HÔPITAL ET CENTRE DE RÉADAPTATION DE JONQUIÈRE,51224541,16,9,0,0,pas d'information disponible,10,12.97,5.1,12:58,5:06,6:00:00,2026-10-25T6:45
''';

void main() {
  group('relevé du MSSS', () {
    final snapshot = parseMsssHourly(_csv);

    test('garde seulement les trois urgences de Saguenay, dans l’ordre', () {
      expect(snapshot.rooms.map((r) => r.hospital), ['Chicoutimi', 'Jonquière', 'La Baie']);
    });

    test('lit l’heure sans zéro', () {
      expect(snapshot.takenAt, DateTime(2026, 10, 25, 6, 45));
    });

    test('calcule l’occupation et tolère les champs vides', () {
      final chicoutimi = snapshot.rooms.first;
      expect(chicoutimi.occupancyPercent, 83);
      final jonquiere = snapshot.rooms[1];
      expect(jonquiere.present, isNull);
      expect(jonquiere.waiting, 10);
    });
  });

  group('couches ArcGIS de la Ville', () {
    test('les dates sont l’heure locale déguisée en UTC', () {
      // Avis 2026-376 : « le lundi 26 octobre, de 8 h à 15 h ».
      expect(arcgisWallTime(1793001600000), DateTime(2026, 10, 26, 8));
      expect(arcgisWallTime(1793026800000), DateTime(2026, 10, 26, 15));
    });

    test('avis d’aqueduc', () {
      final notices = parseWaterNotices({
        'features': [
          {
            'attributes': {
              'avis_no': '2026-378',
              'type_avis': 'Avis d’ébullition',
              'avis_desc': ' Avis en vigueur. ',
              'date_actif': 1792861990556,
              'date_fin': null,
              'created_by': 'ne pas lire',
            },
          },
        ],
      });
      expect(notices.single.type, WaterNoticeType.boil);
      expect(notices.single.end, isNull);
      expect(notices.single.zone, 'Avis en vigueur.');
    });

    test('travaux', () {
      final works = parseRoadworks({
        'features': [
          {
            'attributes': {
              'nom_complet': 'Rue Saint-Pierre',
              'fermeture_etat': 'Circulation locale',
              'remarque': 'Pavage.',
              'date_actif': 1792479600000,
              'date_fin': 1793120400000,
            },
          },
        ],
      });
      expect(works.single.shortName, 'Saint-Pierre');
      expect(works.single.status, 'circulation locale');
      expect(works.single.start, DateTime(2026, 10, 20, 7));
    });
  });
}
