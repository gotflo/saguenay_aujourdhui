import 'address.dart';
import 'collection.dart';
import 'place.dart';
import 'roadwork.dart';
import 'transit.dart';
import 'water.dart';

/// Une vraie adresse et ce qui la concerne, à partir des relevés en direct :
/// les avis dont la zone la couvre, les chantiers proches, son horaire de
/// collecte et ses arrêts de bus.
Place livePlace(
  ResolvedAddress address, {
  CollectionSchedule? collection,
  StopSchedule? stop,
  WaterSnapshot? water,
  RoadworkSnapshot? roadworks,
  String? collectionMissingNote,
}) => Place(
  id: address.id,
  label: address.label,
  shortLabel: address.shortLabel,
  collection: collection ?? const CollectionSchedule({}),
  collectionMissing: collection == null,
  collectionMissingNote: collectionMissingNote,
  stop: stop,
  waterNotices: [
    for (final n in water?.notices ?? const <WaterNotice>[])
      if (n.covers(address.lat, address.lon)) n.number,
  ],
  roadworks: roadworks?.near(address.lat, address.lon, street: address.street) ?? const [],
  lat: address.lat,
  lon: address.lon,
  sector: address.sector,
);
