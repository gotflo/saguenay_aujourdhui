enum SignalKind { water, weather, power, roads, parking, collection, bus, roadwork, emergency }

/// Ce qu'une tuile affiche sous la carte principale.
class Tile {
  const Tile({
    required this.kind,
    required this.label,
    required this.value,
    required this.detail,
    this.quiet = false,
  });

  final SignalKind kind;
  final String label;
  final String value;
  final String detail;

  /// Une tuile « calme » rappelle que tout va bien (pas d'avis, par exemple).
  final bool quiet;
}

/// Une information utile à un moment donné, avec ce qu'il faut pour la classer.
class Signal {
  const Signal({
    required this.kind,
    required this.label,
    required this.title,
    required this.body,
    required this.why,
    required this.weight,
    required this.urgency,
    required this.tile,
    this.critical = false,
    this.notify = false,
  });

  final SignalKind kind;

  /// Petit mot au-dessus du titre : « Cette nuit », « Ton bus »...
  final String label;
  final String title;
  final String body;

  /// Une phrase pour « Pourquoi je vois ça ? ».
  final String why;

  /// Importance de l'information en soi, de 0 à 1.
  final double weight;

  /// À quel point c'est le moment, de 0 à 1.
  final double urgency;

  final Tile tile;

  /// S'affiche en rouge (avis d'ébullition).
  final bool critical;

  /// Mérite une notification immédiate.
  final bool notify;

  int get score => (100 * weight * urgency).round();
}
