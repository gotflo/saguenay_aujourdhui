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
      final a = ask('Quel hôpital est le moins plein ?');
      expect(a.text, contains('Chicoutimi 83 %'));
      expect(a.text, contains('911'));
    });

    test('urgences : sans chiffres, pas de phrase vide', () {
      final a = ask('Les urgences ?', city: const CityData());
      expect(a.text, startsWith('Je n’ai pas les chiffres'));
      expect(a.text, contains('911'));
    });

    test('le bac nommé d’abord', () {
      expect(ask('Quand passe le bac brun ?').text, startsWith('Compost'));
      expect(ask('Le compost, c’est quand ?').text, startsWith('Compost'));
      expect(ask('Les ordures passent quand ?').text, startsWith('Ordures'));
    });

    test('ce qui n’est pas compris le dit', () {
      final a = ask('Quelle est la capitale du Pérou ?');
      expect(a.understood, isFalse);
    });
  });

  group('qui répond', () {
    void local(List<String> questions) {
      for (final q in questions) {
        expect(ask(q).understood, isTrue, reason: q);
      }
    }

    void online(List<String> questions) {
      for (final q in questions) {
        expect(ask(q).understood, isFalse, reason: q);
      }
    }

    test('ce que l’app sait dire seule reste sur le téléphone', () {
      local([
        'Le bac, c’est quand ?',
        'Quel jour passe le compost ?',
        'Est-ce que je sors mes vidanges ce soir ?',
        'Je peux me stationner sur ma rue ce soir ?',
        'Interdit de stationner cette nuit ?',
        'L’eau est-elle bonne à boire ?',
        'Puis-je boire l’eau ?',
        'Prochain bus ?',
        'À quelle heure passe le bus ?',
        'Va-t-il neiger cette nuit ?',
        'Il va pleuvoir ?',
        'Météo ?',
        'Il y a une panne ?',
        'Y a-t-il des coupures d’électricité ?',
        'Comment est la route 175 ?',
        'Il y a des travaux près de chez moi ?',
        'Il y a quoi demain ?',
        'Une canette, ça va où ?',
        'Où jeter des piles ?',
        'Bonjour',
      ]);
    });

    test('une explication, un prix, un numéro : en ligne, jamais « Oui » à côté', () {
      online([
        'Pourquoi faire bouillir l’eau pendant une minute ?',
        'C’est quoi un avis d’ébullition ?',
        'Pourquoi je n’ai pas le droit de me stationner l’hiver ?',
        'Combien coûte le bus ?',
        'Comment fonctionne le bac brun ?',
        'Quel est le numéro de la Ville ?',
        'Mon bac n’a pas été ramassé, je fais quoi ?',
        'Où stationner pendant l’interdiction de nuit ?',
        'Quand passe la déneigeuse ?',
        'Où est l’hôpital de Jonquière ?',
      ]);
    });

    test('un état que l’app n’a pas : en ligne', () {
      online([
        'Mon eau est brune, c’est normal ?',
        'Ma facture d’Hydro est trop élevée',
        'Le bus est-il gratuit pour les étudiants ?',
        'Mon bac est brisé',
        'Il y a une urgence vétérinaire ?',
        'Je veux acheter du bacon',
      ]);
    });

    test('un autre jour, un autre endroit, un autre trajet : en ligne', () {
      online([
        'Va-t-il neiger samedi ?',
        'Quelle température demain ?',
        'Je peux me garer samedi prochain ?',
        'Il y a une panne à Jonquière ?',
        'L’eau est bonne à La Baie ?',
        'Le bus 10 passe à quelle heure dimanche ?',
        'Quel bus pour aller à l’UQAC ?',
        'Comment est la route 170 ?',
      ]);
    });

    test('une suite dépend de la question d’avant', () {
      online(['Et demain ?', 'Et pour le bac brun ?']);
    });

    test('deux sujets : en ligne, et les deux réponses si le réseau manque', () {
      final a = ask('Je sors le bac et je peux stationner dans la rue ce soir ?');
      expect(a.understood, isFalse);
      expect(a.text, contains('cette nuit'));
      expect(a.text, contains('Sors le bac bleu'));
    });

    test('un objet inconnu part en ligne au lieu de redemander l’objet', () {
      final a = ask('Ça va où, un vieux matelas ?');
      expect(a.understood, isFalse);
      expect(a.text, isNot(contains('Dis-moi l’objet')));
      expect(ask('L’eau goûte le chlore').text, isNot(contains('écocentre')));
    });

    test('la fiche du sujet reste proposée avec la réponse en ligne', () {
      expect(ask('Pourquoi faire bouillir l’eau ?').kind, SignalKind.water);
    });
  });

  group('danger', () {
    test('le 911 d’abord, sans réseau et sans passer par l’assistant en ligne', () {
      for (final q in [
        'Mon père ne respire plus',
        'J’ai très mal à la poitrine',
        'Je sens une odeur de gaz chez moi',
        'Il y a le feu chez mon voisin',
        'Mon enfant s’étouffe',
        'Ma voisine a fait une chute, elle saigne beaucoup',
      ]) {
        final a = ask(q);
        expect(a.understood, isTrue, reason: q);
        expect(a.text, startsWith('Appelle le 911'), reason: q);
      }
    });

    test('la détresse : une ligne d’aide, tout de suite', () {
      for (final q in ['Je veux me suicider', 'J’ai des idées noires, je veux en finir']) {
        final a = ask(q);
        expect(a.understood, isTrue, reason: q);
        expect(a.text, contains('1 866 APPELLE'), reason: q);
        expect(a.text, contains('911'), reason: q);
      }
    });

    test('un feu de camp n’appelle pas le 911', () {
      expect(ask('Puis-je faire un feu dans ma cour ?').text, isNot(contains('911')));
    });
  });

  group('ce qui part en ligne', () {
    test('le secteur et les états, jamais l’adresse ni « ta rue »', () {
      final b = assistant.briefing(racine, Demo.city, DateTime(2026, 10, 26, 18));
      expect(b['secteur'], 'Chicoutimi');
      expect(b['eau'], contains('Aucun avis'));
      expect(b['stationnement'], contains('15 novembre'));
      expect(b['collectes'], startsWith('Recyclage demain'));
      final all = b.toString();
      expect(all, isNot(contains('201')));
      expect(all, isNot(contains('ta rue')));
    });

    test('les prévisions du bulletin suivent', () {
      final city = CityData(
        weather: WeatherSnapshot(
          takenAt: DateTime(2026, 10, 26, 17),
          forecast: const ['Samedi : Neige. Maximum moins 2.'],
        ),
      );
      final b = assistant.briefing(racine, city, DateTime(2026, 10, 26, 18));
      expect(b['previsions'], ['Samedi : Neige. Maximum moins 2.']);
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
