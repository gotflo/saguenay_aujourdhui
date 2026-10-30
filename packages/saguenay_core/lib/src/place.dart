import 'collection.dart';
import 'roadwork.dart';
import 'transit.dart';

/// Une adresse et tout ce qui la concerne.
class Place {
  const Place({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.collection,
    this.collectionIsExample = false,
    this.stop,
    this.waterNotices = const [],
    this.roadworks = const [],
    this.lat,
    this.lon,
    this.sector,
    this.collectionMissing = false,
    this.collectionMissingNote,
  });

  final String id;
  final String label;
  final String shortLabel;
  final CollectionSchedule collection;

  /// Vrai quand le calendrier est inventé pour la démo.
  final bool collectionIsExample;

  final StopSchedule? stop;

  /// Numéros des avis d'aqueduc dont la zone couvre l'adresse.
  final List<String> waterNotices;
  final List<NearbyRoadwork> roadworks;

  /// Coordonnées, pour les pannes d'électricité et les alertes météo.
  final double? lat;
  final double? lon;

  /// « Chicoutimi », « Jonquière »...
  final String? sector;

  /// L'horaire des collectes n'a pas encore pu être lu (pas de réseau au
  /// premier lancement, par exemple).
  final bool collectionMissing;

  /// Pourquoi l'horaire manque, quand ce n'est pas le réseau.
  final String? collectionMissingNote;

  /// La même adresse avec un autre arrêt : celui de l'endroit où l'on est.
  Place withStop(StopSchedule? value) => Place(
    id: id,
    label: label,
    shortLabel: shortLabel,
    collection: collection,
    collectionIsExample: collectionIsExample,
    stop: value,
    waterNotices: waterNotices,
    roadworks: roadworks,
    lat: lat,
    lon: lon,
    sector: sector,
    collectionMissing: collectionMissing,
    collectionMissingNote: collectionMissingNote,
  );
}
