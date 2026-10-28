import 'geo.dart';

enum SortingPlace {
  brown('le bac brun'),
  blue('le bac bleu'),
  garbage('la poubelle'),
  ecocentre('l’écocentre'),
  pharmacy('la pharmacie'),
  notBrown('pas dans le bac brun'),
  notBlue('pas dans le bac bleu');

  const SortingPlace(this.label);

  final String label;
}

class SortingAnswer {
  const SortingAnswer(this.item, this.place, this.note);

  /// L'objet reconnu : « boîte de pizza ».
  final String item;
  final SortingPlace place;
  final String note;
}

/// Ce qui va où, d'après les pages de la Ville de Saguenay (bac brun :
/// « Matières acceptées et refusées » ; bac bleu : « Matières recyclables et
/// non recyclables »). Quand la Ville dit seulement « refusé », on le dit
/// tel quel et on renvoie vers Ça va où? de RECYC-QUÉBEC.
abstract final class SortingGuide {
  static const source = 'Ville de Saguenay, pages du bac brun et du bac bleu';

  static const _brown =
      'Ça se mange, c’est du papier ou du carton sale non ciré, ou c’est un résidu de jardin.';
  static const _blue = 'C’est un contenant, un emballage ou un imprimé.';
  static const _rdd =
      'Résidu domestique dangereux : interdit dans tous les bacs, il peut déclencher un incendie.';

  // Mot-clé (sans accents, au singulier) → réponse. Les plus précis d'abord.
  static const _rules = <(String, String, SortingPlace, String)>[
    // Bac brun : papier et carton sales
    ('boite de pizza', 'boîte de pizza', SortingPlace.brown, 'Carton sale non ciré. $_brown'),
    ('contenant de frite', 'contenant de frites', SortingPlace.brown, 'Carton sale non ciré.'),
    ('papier parchemin', 'papier parchemin', SortingPlace.brown, 'Accepté au bac brun.'),
    ('essuie tout', 'essuie-tout', SortingPlace.brown, 'Papier sale. $_brown'),
    ('serviette de table', 'serviette de table', SortingPlace.brown, 'Papier sale.'),
    ('mouchoir', 'mouchoirs', SortingPlace.brown, 'Papier sale.'),
    ('moule a muffin', 'moules à muffins en papier', SortingPlace.brown, 'Papier sale.'),
    ('paille en carton', 'paille en carton', SortingPlace.brown, 'Carton.'),
    (
      'vaisselle en carton',
      'vaisselle en carton non cirée',
      SortingPlace.brown,
      'Carton non ciré.',
    ),
    ('filtre a cafe', 'filtre à café', SortingPlace.brown, 'Avec le marc.'),
    ('sachet de the', 'sachet de thé', SortingPlace.brown, 'Accepté au bac brun.'),
    ('marc de cafe', 'marc de café', SortingPlace.brown, 'Accepté au bac brun.'),
    // Bac brun : aliments
    ('coquille d oeuf', 'coquilles d’œufs', SortingPlace.brown, 'Accepté au bac brun.'),
    ('os', 'os', SortingPlace.brown, 'Viandes crues ou cuites, même les petits os.'),
    ('viande', 'viande', SortingPlace.brown, _brown),
    ('poisson', 'poisson', SortingPlace.brown, _brown),
    ('fruit de mer', 'fruits de mer', SortingPlace.brown, 'Crabes et homards compris.'),
    ('homard', 'homard', SortingPlace.brown, 'Carapace comprise.'),
    ('crabe', 'crabe', SortingPlace.brown, 'Carapace comprise.'),
    ('pelure', 'pelures', SortingPlace.brown, _brown),
    ('noyau', 'noyaux', SortingPlace.brown, _brown),
    ('fruit', 'fruits', SortingPlace.brown, _brown),
    ('legume', 'légumes', SortingPlace.brown, _brown),
    ('pain', 'pain', SortingPlace.brown, _brown),
    ('pate', 'pâtes', SortingPlace.brown, _brown),
    ('riz', 'riz', SortingPlace.brown, _brown),
    ('fromage', 'fromage', SortingPlace.brown, 'Produits laitiers acceptés.'),
    ('yogourt', 'yogourt', SortingPlace.brown, 'Sans le contenant, qui va au bac bleu.'),
    ('reste de table', 'restes de table', SortingPlace.brown, 'Cuits, crus, frais ou périmés.'),
    ('reste de repas', 'restes de repas', SortingPlace.brown, 'Cuits, crus, frais ou périmés.'),
    ('aliment perime', 'aliments périmés', SortingPlace.brown, 'Sans leur emballage.'),
    ('huile de cuisson', 'huile de cuisson', SortingPlace.brown, 'En petite quantité seulement.'),
    (
      'nourriture pour animaux',
      'nourriture pour animaux',
      SortingPlace.brown,
      'Acceptée au bac brun.',
    ),
    // Bac brun : jardin et divers
    ('gazon', 'gazon', SortingPlace.brown, 'La Ville encourage aussi l’herbicyclage.'),
    (
      'feuille morte',
      'feuilles mortes',
      SortingPlace.brown,
      'La Ville encourage aussi le feuillicyclage.',
    ),
    (
      'branche',
      'petites branches',
      SortingPlace.brown,
      'Moins de 2 cm de diamètre et de 60 cm de long. Les plus grosses sont refusées au bac brun.',
    ),
    ('taille de haie', 'tailles de haies', SortingPlace.brown, 'Résidu de jardin.'),
    (
      'plante',
      'plantes et fleurs',
      SortingPlace.brown,
      'Sauf les plantes exotiques envahissantes.',
    ),
    ('terre', 'terre de jardin', SortingPlace.brown, 'Terre de rempotage et de jardin acceptée.'),
    ('cendre', 'cendres froides', SortingPlace.brown, 'Refroidies au moins sept jours.'),
    ('cheveu', 'cheveux et poils', SortingPlace.brown, 'Acceptés au bac brun.'),
    ('cure dent', 'cure-dents', SortingPlace.brown, 'Le bois est accepté.'),
    ('baton de popsicle', 'bâton de friandise glacée', SortingPlace.brown, 'Le bois est accepté.'),
    ('ustensile en bois', 'ustensiles en bois', SortingPlace.brown, 'Le bois est accepté.'),
    // Bac bleu
    (
      'carton de lait',
      'carton de lait',
      SortingPlace.blue,
      'C’est un contenant. Refusé au bac brun, sans exception.',
    ),
    ('boite a oeuf', 'boîte à œufs', SortingPlace.blue, 'Emballage. $_blue'),
    ('casseau', 'casseau de fruits', SortingPlace.blue, 'Emballage.'),
    ('conserve', 'boîte de conserve', SortingPlace.blue, 'Emballage de métal.'),
    ('canette', 'canette', SortingPlace.blue, 'Contenant de métal.'),
    (
      'papier d aluminium',
      'papier d’aluminium',
      SortingPlace.blue,
      'Avec les assiettes d’aluminium.',
    ),
    ('assiette d aluminium', 'assiette d’aluminium', SortingPlace.blue, 'Emballage de métal.'),
    ('bouteille de shampoing', 'bouteille de shampoing', SortingPlace.blue, 'Contenant.'),
    ('bouteille', 'bouteille', SortingPlace.blue, 'Contenant de verre ou de plastique.'),
    ('pot en verre', 'pot en verre', SortingPlace.blue, 'Contenant.'),
    ('pot de yogourt', 'pot de yogourt', SortingPlace.blue, 'Contenant, une fois vidé.'),
    ('contenant de plastique', 'contenant de plastique', SortingPlace.blue, 'Contenant.'),
    ('contenant', 'contenant', SortingPlace.blue, _blue),
    ('boite de carton', 'boîte de carton', SortingPlace.blue, 'Emballage propre.'),
    ('carton', 'carton', SortingPlace.blue, 'Propre. Sale et non ciré, il va au bac brun.'),
    (
      'sac de papier',
      'sac de papier',
      SortingPlace.blue,
      'Propre : bac bleu. S’il sert à emballer des restes de table : bac brun.',
    ),
    ('journal', 'journaux', SortingPlace.blue, 'Imprimé.'),
    ('magazine', 'magazines', SortingPlace.blue, 'Imprimé.'),
    ('circulaire', 'circulaires', SortingPlace.blue, 'Imprimé.'),
    ('enveloppe', 'enveloppes', SortingPlace.blue, 'Imprimé.'),
    ('cahier', 'cahiers', SortingPlace.blue, 'Imprimé.'),
    ('papier brun', 'papier brun', SortingPlace.brown, 'Papier sale. $_brown'),
    ('papier', 'papier', SortingPlace.blue, 'Imprimé propre. Sale, il va au bac brun.'),
    // Refusés au bac bleu
    (
      'styromousse',
      'styromousse',
      SortingPlace.notBlue,
      'Le polystyrène de protection est interdit au bac bleu, et refusé au bac brun.',
    ),
    (
      'polystyrene',
      'polystyrène',
      SortingPlace.notBlue,
      'Le polystyrène de protection est interdit au bac bleu, et refusé au bac brun.',
    ),
    ('aerosol', 'contenant d’aérosol', SortingPlace.notBlue, 'Interdit au bac bleu.'),
    // Résidus domestiques dangereux
    ('pile', 'piles', SortingPlace.ecocentre, '$_rdd Il existe aussi des points de dépôt.'),
    ('batterie', 'batteries', SortingPlace.ecocentre, _rdd),
    ('propane', 'bonbonne de propane', SortingPlace.ecocentre, _rdd),
    ('chlore', 'produits chlorés de piscine', SortingPlace.ecocentre, _rdd),
    ('peinture', 'peinture', SortingPlace.ecocentre, _rdd),
    ('huile a moteur', 'huile à moteur', SortingPlace.ecocentre, _rdd),
    ('produit chimique', 'produits chimiques', SortingPlace.ecocentre, _rdd),
    (
      'medicament',
      'médicaments',
      SortingPlace.pharmacy,
      'Refusés au bac brun. Les pharmacies les reprennent.',
    ),
    // Refusés au bac brun
    (
      'sac compostable',
      'sac compostable',
      SortingPlace.notBrown,
      'Même certifiés, les sacs compostables ou biodégradables sont refusés. Seuls les sacs de papier sont acceptés.',
    ),
    (
      'sac biodegradable',
      'sac biodégradable',
      SortingPlace.notBrown,
      'Même certifiés, refusés. Seuls les sacs de papier sont acceptés.',
    ),
    ('couche', 'couches', SortingPlace.notBrown, 'Refusées au bac brun.'),
    ('lingette', 'lingettes', SortingPlace.notBrown, 'Refusées au bac brun.'),
    ('dosette', 'dosettes de café', SortingPlace.notBrown, 'Refusées au bac brun.'),
    ('megot', 'mégots', SortingPlace.notBrown, 'Refusés au bac brun.'),
    ('gomme', 'gomme à mâcher', SortingPlace.notBrown, 'Refusée au bac brun.'),
    (
      'litiere',
      'litière agglomérante',
      SortingPlace.notBrown,
      'La litière agglomérante est refusée ; la litière en copeaux de rongeurs, d’oiseaux ou de lapins est acceptée.',
    ),
    ('aspirateur', 'poussière d’aspirateur', SortingPlace.notBrown, 'Refusée au bac brun.'),
    (
      'verre de cafe',
      'verre de café de restaurant',
      SortingPlace.notBrown,
      'Les verres des chaînes de restauration rapide sont refusés.',
    ),
    (
      'tissu',
      'tissus et vêtements',
      SortingPlace.notBrown,
      'Refusés au bac brun ; pensez au réemploi.',
    ),
    ('bois traite', 'bois traité, teint ou peint', SortingPlace.ecocentre, 'Refusé au bac brun.'),
    (
      'materiaux de construction',
      'matériaux de construction',
      SortingPlace.ecocentre,
      'Refusés au bac brun.',
    ),
  ];

  /// Toutes les règles, une par ligne : la référence donnée à l'assistant en
  /// ligne pour qu'il réponde d'après la Ville et non de mémoire.
  static String get reference => [
    'Bac brun : $_brown',
    'Bac bleu : $_blue',
    _rdd,
    for (final (_, item, place, note) in _rules) '$item : ${place.label}. $note',
  ].join('\n');

  /// La meilleure correspondance dans la phrase, ou `null`.
  static SortingAnswer? lookup(String text) {
    final t = ' ${_singular(streetKey(text))} ';
    for (final (key, item, place, note) in _rules) {
      if (t.contains(' $key ')) return SortingAnswer(item, place, note);
    }
    return null;
  }

  static String _singular(String s) => s
      .split(' ')
      .map(
        (w) => w.length > 3 && (w.endsWith('s') || w.endsWith('x')) && !w.endsWith('ss')
            ? w.substring(0, w.length - 1)
            : w,
      )
      .join(' ');
}
