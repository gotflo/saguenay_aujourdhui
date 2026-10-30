import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saguenay_core/saguenay_core.dart';

import 'addresses.dart';
import 'providers.dart';

/// Une position du téléphone.
typedef LatLon = ({double lat, double lon});

/// Où est le téléphone, seulement pendant qu'on regarde l'app. La position
/// sert au calcul sur le téléphone et n'est envoyée nulle part.
abstract class LocationSource {
  /// Demande la permission « pendant l'utilisation de l'app ».
  Future<bool> ensurePermission();

  Stream<LatLon> watch();
}

class DeviceLocation implements LocationSource {
  const DeviceLocation();

  @override
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Une nouvelle position tous les 50 m environ : assez pour changer d'arrêt.
  @override
  Stream<LatLon> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
  ).map((p) => (lat: p.latitude, lon: p.longitude));
}

/// Le web et les tests : pas de position.
class NoLocation implements LocationSource {
  const NoLocation();

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Stream<LatLon> watch() => const Stream.empty();
}

/// Remplacé dans `main()` sur le téléphone.
final locationSourceProvider = Provider<LocationSource>((ref) => const NoLocation());

/// L'app est-elle à l'écran ? Hors de l'écran, on ne lit plus la position.
final appInForegroundProvider = NotifierProvider<AppInForeground, bool>(AppInForeground.new);

class AppInForeground extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

/// A-t-on choisi de voir les arrêts de l'endroit où l'on est ?
final busPositionProvider = NotifierProvider<BusPosition, bool>(BusPosition.new);

class BusPosition extends Notifier<bool> {
  static const key = 'bus-position';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(key) ?? false;

  /// Demande la permission ; vrai si on peut maintenant suivre la position.
  Future<bool> enable() async {
    if (!await ref.read(locationSourceProvider).ensurePermission()) return false;
    state = true;
    await ref.read(sharedPrefsProvider).setBool(key, true);
    return true;
  }

  Future<void> disable() async {
    state = false;
    await ref.read(sharedPrefsProvider).setBool(key, false);
  }
}

/// La position, tant que l'app est à l'écran et qu'on l'a choisi. Rien
/// pendant un moment rejoué en démo.
final positionProvider = StreamProvider<LatLon?>((ref) {
  if (kIsWeb ||
      !ref.watch(busPositionProvider) ||
      !ref.watch(appInForegroundProvider) ||
      ref.watch(demoMomentProvider) != null) {
    return Stream.value(null);
  }
  return ref.watch(locationSourceProvider).watch().handleError((Object e) {
    debugPrint('Position non lue : $e');
  });
});

// Flux de la STS gardé sur le téléphone -------------------------------------------------

/// Le flux GTFS de la STS, gardé une semaine dans un fichier : l'horaire de
/// l'adresse et les arrêts près de soi en viennent tous les deux.
abstract class GtfsStore {
  Future<Uint8List?> read();

  Future<void> write(Uint8List zip);
}

class FileGtfsStore implements GtfsStore {
  const FileGtfsStore();

  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/sts_gtfs.zip');

  @override
  Future<Uint8List?> read() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      final age = DateTime.now().difference(f.lastModifiedSync());
      if (age > const Duration(days: 7)) return null;
      return await f.readAsBytes();
    } on Object catch (e) {
      debugPrint('Flux de la STS gardé illisible : $e');
      return null;
    }
  }

  @override
  Future<void> write(Uint8List zip) async {
    try {
      await (await _file()).writeAsBytes(zip, flush: true);
    } on Object catch (e) {
      debugPrint('Flux de la STS non gardé : $e');
    }
  }
}

class NoGtfsStore implements GtfsStore {
  const NoGtfsStore();

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List zip) async {}
}

final gtfsStoreProvider = Provider<GtfsStore>(
  (ref) => kIsWeb ? const NoGtfsStore() : const FileGtfsStore(),
);

/// Le flux GTFS : celui gardé de moins d'une semaine, sinon un nouveau.
final gtfsZipProvider = FutureProvider<Uint8List>((ref) async {
  final store = ref.watch(gtfsStoreProvider);
  final kept = await store.read();
  if (kept != null) return kept;
  final zip = await ref.read(gtfsFetchProvider)();
  await store.write(zip);
  return zip;
});

// Les arrêts près de soi --------------------------------------------------------------

/// Au-delà de cette distance de l'adresse, on n'est plus chez soi.
const awayFromHomeMeters = 350.0;

/// Les départs du jour pour tous les arrêts, calculés une fois par jour dans
/// un isolat, et seulement si on a choisi de suivre sa position.
final transitDayProvider = FutureProvider<TransitDay?>((ref) async {
  if (kIsWeb || !ref.watch(busPositionProvider)) return null;
  final day = ref.watch(realDayProvider);
  try {
    final zip = await ref.watch(gtfsZipProvider.future);
    return await _dayInBackground(zip, day);
  } on Object catch (e) {
    debugPrint('Départs du jour non calculés : $e');
    return null;
  }
});

/// Dans une fonction à part : la fermeture n'emporte que ces valeurs vers l'isolat.
Future<TransitDay> _dayInBackground(Uint8List zip, DateTime day) =>
    Isolate.run(() => transitDayFor(zip, day));

/// Hors de chez soi, l'horaire des arrêts les plus proches de l'endroit où
/// l'on est. `null` à la maison, sans position ou loin de tout arrêt.
final nearbyStopProvider = Provider<StopSchedule?>((ref) {
  final here = ref.watch(positionProvider).value;
  final place = ref.watch(savedPlaceProvider);
  if (here == null || place == null) return null;
  final lat = place.lat, lon = place.lon;
  if (lat != null &&
      lon != null &&
      distanceKm(lat, lon, here.lat, here.lon) * 1000 <= awayFromHomeMeters) {
    return null;
  }
  return ref.watch(transitDayProvider).value?.around(here.lat, here.lon);
});
