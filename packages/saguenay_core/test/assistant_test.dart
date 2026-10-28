import 'package:saguenay_core/saguenay_core.dart';
import 'package:test/test.dart';

void main() {
  const assistant = LocalAssistant();
  final racine = Demo.place('racine');
  final saintJean = Demo.place('saint-jean');
  AssistantAnswer ask(String q, {Place? place, DateTime? at, CityData? city}) =>
      assistant.answer(q, place ?? racine, city ?? Demo.city, at ?? DateTime(2026, 10, 26, 18));

  group('tri, d’après les pages de la Ville', () {
    test('une boîte de pizza va au bac brun', () {
      final a = ask('Ça va où, une boîte de pizza ?');
      expect(a.text, startsWith('Boîte de pizza : le bac brun.'));
      expect(a.sources, [SortingGuide.source]);
    });

    test('un carton de lait va au bac bleu, jamais au bac brun', () {
      expect(ask('carton de lait, quel bac ?').text, contains('le bac bleu'));
    });

    test('les piles vont à l’écocentre : risque d’incendie', () {
      final a = ask('Où jeter des piles ?');
      expect(a.text, contains('l’écocentre'));
      expect(a.text, contains('incendie'));
    });

    test('les sacs compostables sont refusés, même certifiés', () {
      expect(ask('je peux mettre un sac compostable ?').text, contains('pas dans le bac brun'));
    });

    test('un objet inconnu renvoie vers Ça va où?', () {
      expect(ask('ça va où ?').text, contains('Ça va où?'));
    });

    test('pluriels et accents', () {
      expect(SortingGuide.lookup('Des coquilles d’œufs')?.place, SortingPlace.brown);
      expect(SortingGuide.lookup('BOITES DE CONSERVE')?.place, SortingPlace.blue);
    });
  });

  group('questions du quotidien', () {
    test('« je sors quel bac cette semaine ? » : le calendrier, pas le tri', () {
      for (final q in [
        'Je sors quel bac cette semaine ?',
        'Quand passe le recyclage ?',
        'Quel bac je sors demain ?',
      ]) {
        expect(ask(q).kind, SignalKind.collection, reason: q);
        expect(ask(q).sources, contains('Horaire des collectes de la Ville'), reason: q);
      }
      expect(ask('Le journal, quel bac ?').text, contains('le bac bleu'));
      // Une date abrégée en fin de phrase ne double pas le point.
      expect(ask('Je sors quel bac cette semaine ?').text, isNot(contains('..')));
    });

    test('le bac : la prochaine collecte et quoi faire ce soir', () {
      final a = ask('Le bac, c’est quand ?');
      expect(a.text, startsWith('Recyclage demain. Sors le bac bleu ce soir.'));
      expect(a.kind, SignalKind.collection);
    });

    test('stationnement : permis en octobre, interdit en hiver', () {
      expect(ask('Je peux me stationner dans la rue cette nuit ?').text, startsWith('Oui'));
      expect(
        ask('je peux laisser mon auto dans la rue ?', at: DateTime(2026, 11, 20, 20)).text,
        startsWith('Non'),
      );
    });

    test('l’eau : un avis d’ébullition à l’adresse', () {
      expect(
        ask('L’eau est-elle potable ?', place: saintJean, at: DateTime(2026, 10, 25, 9)).text,
        startsWith('Non'),
      );
      expect(ask('l’eau est bonne ?').text, startsWith('Oui'));
    });

    test('le bus : la même réponse que la carte', () {
      expect(
        ask('Prochain bus ?', at: DateTime(2026, 11, 18, 7, 35)).text,
        startsWith('Le 105 passe dans 11 min.'),
      );
    });

    test('urgences : les chiffres, avec la mise en garde', () {
      final a = ask('Il y a combien d’attente à l’urgence ?');
      expect(a.text, contains('Chicoutimi 83 %'));
      expect(a.text, contains('911'));
    });

    test('ce qui n’est pas compris le dit', () {
      final a = ask('Quelle est la capitale du Pérou ?');
      expect(a.understood, isFalse);
    });
  });

  group('calendrier', () {
    test('les collectes, avec un rappel la veille', () {
      final ics = calendarExport(
        racine,
        DateTime(2026, 10, 25),
        days: 30,
        stamp: DateTime.utc(2026, 10, 25, 12),
      );
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(calendarHasCollection(ics, DateTime(2026, 10, 27), [WasteStream.recycling]), isTrue);
      expect(ics, contains('TRIGGER:-PT5H'));
      expect(ics, contains('Première nuit sans auto dans la rue'));
      expect('BEGIN:VEVENT'.allMatches(ics).length, 'END:VEVENT'.allMatches(ics).length);
    });

    test('les virgules et points-virgules sont protégés', () {
      final ics = calendarExport(racine, DateTime(2026, 10, 25), days: 1);
      expect(ics, contains(r'201\, rue Racine Est'));
    });
  });
}
