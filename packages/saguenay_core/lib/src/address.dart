/// Une proposition du géocodeur du Québec, pendant qu'on tape.
class AddressSuggestion {
  const AddressSuggestion({required this.label, required this.lat, required this.lon});

  /// « 201 rue Racine Est, Saguenay G7H1S3 ».
  final String label;
  final double lat;
  final double lon;
}

/// Une adresse retrouvée dans la couche d'adresses de la Ville : avec son
/// secteur, ce qu'il faut pour lire l'horaire des collectes.
class ResolvedAddress {
  const ResolvedAddress({
    required this.civic,
    required this.street,
    required this.sector,
    required this.lat,
    required this.lon,
  });

  factory ResolvedAddress.fromJson(Map<String, Object?> json) => ResolvedAddress(
    civic: json['civic'] as String,
    street: json['street'] as String,
    sector: json['sector'] as String,
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
  );

  /// « 201 ».
  final String civic;

  /// « Rue Racine Est ».
  final String street;

  /// « Chicoutimi », « Jonquière », « La Baie »...
  final String sector;
  final double lat;
  final double lon;

  /// Stable pour une même adresse : sert de clé aux relevés gardés.
  String get id => 'adr:${civic.toLowerCase()}:${street.toLowerCase()}:${sector.toLowerCase()}';

  /// « 201, rue Racine Est ».
  String get label => '$civic, ${_lowerType(street)}';

  /// « Racine Est », pour le widget.
  String get shortLabel => street.replaceFirst(
    RegExp(
      r'^(Rue|Boulevard|Boul\.|Avenue|Chemin|Route|Rang|Montée|Place|Côte|Croissant|Impasse)\s+(de la |des |du |de l’|de l\x27|de )?',
      caseSensitive: false,
    ),
    '',
  );

  static String _lowerType(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  Map<String, Object?> toJson() => {
    'civic': civic,
    'street': street,
    'sector': sector,
    'lat': lat,
    'lon': lon,
  };
}

/// Numéros de secteur du formulaire des collectes de la Ville.
const saguenaySectors = {
  'Canton Tremblay': 4,
  'Chicoutimi': 3,
  'Jonquière': 7,
  'La Baie': 1,
  'Lac Kénogami': 8,
  'Laterrière': 2,
  'Shipshaw': 5,
};

/// Le secteur d'après le nom donné par la couche d'adresses, sans tenir
/// compte des majuscules ni des accents.
int? sectorNumber(String sector) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp('[éèê]'), 'e').replaceAll(RegExp(r'[^a-z]'), '');
  final k = norm(sector);
  for (final e in saguenaySectors.entries) {
    if (norm(e.key) == k) return e.value;
  }
  return null;
}
