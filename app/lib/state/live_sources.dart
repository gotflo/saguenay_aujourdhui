import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';
import 'web_relay.dart';

enum SourceOrigin {
  /// Lu à l'instant à la source.
  live,

  /// Le dernier relevé réussi, gardé sur le téléphone.
  cached,

  /// Le relevé du 25 octobre 2026, quand rien d'autre n'est disponible.
  demo,

  /// Rien de disponible : pas de réseau et pas encore de relevé gardé.
  none,
}

class LiveStatus<T> {
  const LiveStatus(this.snapshot, this.origin);

  final T? snapshot;
  final SourceOrigin origin;

  bool get offline => origin == SourceOrigin.cached || origin == SourceOrigin.none;
}

/// Une source en direct : on la lit, on garde le dernier bon relevé sur le
/// téléphone, et on se rabat dessus quand le réseau manque.
abstract class LiveSource<T> extends AsyncNotifier<LiveStatus<T>> {
  /// Clé du relevé gardé dans les préférences.
  String get cacheKey;

  /// Le serveur accepte-t-il les requêtes d'un navigateur (en-têtes CORS) ?
  bool get worksOnWeb;

  Future<T> fetch();
  Map<String, Object?> encode(T value);
  T decode(Map<String, Object?> json);

  /// Quand rien d'autre n'est disponible.
  T? get demo => null;

  /// Délai avant la prochaine lecture, tant que l'app est ouverte.
  Duration nextRefresh(DateTime now);

  DateTime? _lastSuccess;

  @override
  Future<LiveStatus<T>> build() async {
    final timer = Timer(nextRefresh(DateTime.now()), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
    final prefs = ref.read(sharedPrefsProvider);
    if (kIsWeb && !worksOnWeb) return _fallback(prefs);

    try {
      final value = await fetch();
      _lastSuccess = DateTime.now();
      await prefs.setString(cacheKey, jsonEncode(encode(value)));
      return LiveStatus(value, SourceOrigin.live);
    } on Object catch (e) {
      debugPrint('$cacheKey non mis à jour : $e');
      return _fallback(prefs);
    }
  }

  /// Relit la source, sauf si la dernière lecture date de moins de deux minutes.
  Future<void> refresh({bool force = false}) async {
    final last = _lastSuccess;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 2)) {
      return;
    }
    ref.invalidateSelf();
    await future;
  }

  LiveStatus<T> _fallback(SharedPreferences prefs) {
    final raw = prefs.getString(cacheKey);
    if (raw != null) {
      try {
        return LiveStatus(
          decode((jsonDecode(raw) as Map).cast<String, Object?>()),
          SourceOrigin.cached,
        );
      } on Object catch (e) {
        debugPrint('$cacheKey : relevé gardé illisible ($e)');
        unawaited(prefs.remove(cacheKey));
      }
    }
    final d = demo;
    return d == null ? LiveStatus<T>(null, SourceOrigin.none) : LiveStatus(d, SourceOrigin.demo);
  }
}

// Urgences ----------------------------------------------------------------------

typedef EmergencyStatus = LiveStatus<EmergencySnapshot>;

/// Lit le relevé du ministère. Remplacé dans les tests.
final emergencyFetchProvider = Provider<Future<EmergencySnapshot> Function()>((ref) {
  final client = MsssClient(client: sourceClient());
  ref.onDispose(client.close);
  return client.fetch;
});

final emergenciesProvider = AsyncNotifierProvider<EmergenciesNotifier, EmergencyStatus>(
  EmergenciesNotifier.new,
);

class EmergenciesNotifier extends LiveSource<EmergencySnapshot> {
  @override
  String get cacheKey => 'urgences';

  // Le site du ministère n'envoie pas d'en-tête CORS.
  @override
  bool get worksOnWeb => webRelay != null;

  @override
  Future<EmergencySnapshot> fetch() => ref.read(emergencyFetchProvider)();

  @override
  Map<String, Object?> encode(EmergencySnapshot value) => value.toJson();

  @override
  EmergencySnapshot decode(Map<String, Object?> json) => EmergencySnapshot.fromJson(json);

  @override
  EmergencySnapshot get demo => Demo.emergencies;

  /// Le fichier sort vers HH:45 : on repasse à HH:50. Calculé en minutes, pas
  /// avec une date : la nuit du changement d'heure, 1 h 50 existe deux fois.
  @override
  Duration nextRefresh(DateTime now) {
    final minutes = (50 - now.minute) % 60;
    return Duration(minutes: minutes == 0 ? 60 : minutes, seconds: -now.second);
  }
}

// Météo ----------------------------------------------------------------------------

typedef WeatherStatus = LiveStatus<WeatherSnapshot>;

final weatherFetchProvider = Provider<Future<WeatherSnapshot> Function(double? lat, double? lon)>((
  ref,
) {
  final client = WeatherClient();
  ref.onDispose(client.close);
  return (lat, lon) => client.fetch(lat: lat, lon: lon);
});

final weatherProvider = AsyncNotifierProvider<WeatherNotifier, WeatherStatus>(WeatherNotifier.new);

class WeatherNotifier extends LiveSource<WeatherSnapshot> {
  @override
  String get cacheKey => 'meteo';

  @override
  bool get worksOnWeb => true;

  /// Les alertes dépendent de l'adresse : on relit quand elle change.
  @override
  Future<WeatherStatus> build() {
    ref.watch(savedPlaceProvider.select((p) => p?.id));
    return super.build();
  }

  @override
  Future<WeatherSnapshot> fetch() {
    final place = ref.read(savedPlaceProvider);
    return ref.read(weatherFetchProvider)(place?.lat, place?.lon);
  }

  @override
  Map<String, Object?> encode(WeatherSnapshot value) => value.toJson();

  @override
  WeatherSnapshot decode(Map<String, Object?> json) => WeatherSnapshot.fromJson(json);

  @override
  Duration nextRefresh(DateTime now) => const Duration(minutes: 30);
}

// Électricité --------------------------------------------------------------------

typedef PowerStatus = LiveStatus<PowerSnapshot>;

final powerFetchProvider = Provider<Future<PowerSnapshot> Function()>((ref) {
  final client = HydroClient(client: sourceClient());
  ref.onDispose(client.close);
  return client.fetch;
});

final powerProvider = AsyncNotifierProvider<PowerNotifier, PowerStatus>(PowerNotifier.new);

class PowerNotifier extends LiveSource<PowerSnapshot> {
  @override
  String get cacheKey => 'pannes';

  // Pas d'en-tête CORS chez Hydro-Québec.
  @override
  bool get worksOnWeb => webRelay != null;

  @override
  Future<PowerSnapshot> fetch() => ref.read(powerFetchProvider)();

  @override
  Map<String, Object?> encode(PowerSnapshot value) => value.toJson();

  @override
  PowerSnapshot decode(Map<String, Object?> json) => PowerSnapshot.fromJson(json);

  @override
  Duration nextRefresh(DateTime now) => const Duration(minutes: 10);
}

// Aqueduc et travaux (carte de la Ville) ---------------------------------------------

typedef WaterStatus = LiveStatus<WaterSnapshot>;
typedef RoadworkStatus = LiveStatus<RoadworkSnapshot>;

/// Les couches publiques de la carte de la Ville. Remplacé dans les tests.
final cityLayersProvider = Provider<CityLayersClient>((ref) {
  final client = CityLayersClient();
  ref.onDispose(client.close);
  return client;
});

final waterLayerProvider = AsyncNotifierProvider<WaterLayerNotifier, WaterStatus>(
  WaterLayerNotifier.new,
);

class WaterLayerNotifier extends LiveSource<WaterSnapshot> {
  @override
  String get cacheKey => 'aqueduc';

  @override
  bool get worksOnWeb => true;

  @override
  Future<WaterSnapshot> fetch() => ref.read(cityLayersProvider).water();

  @override
  Map<String, Object?> encode(WaterSnapshot value) => value.toJson();

  @override
  WaterSnapshot decode(Map<String, Object?> json) => WaterSnapshot.fromJson(json);

  @override
  Duration nextRefresh(DateTime now) => const Duration(minutes: 10);
}

final roadworksLayerProvider = AsyncNotifierProvider<RoadworksLayerNotifier, RoadworkStatus>(
  RoadworksLayerNotifier.new,
);

class RoadworksLayerNotifier extends LiveSource<RoadworkSnapshot> {
  @override
  String get cacheKey => 'travaux';

  @override
  bool get worksOnWeb => true;

  @override
  Future<RoadworkSnapshot> fetch() => ref.read(cityLayersProvider).roadworks();

  @override
  Map<String, Object?> encode(RoadworkSnapshot value) => value.toJson();

  @override
  RoadworkSnapshot decode(Map<String, Object?> json) => RoadworkSnapshot.fromJson(json);

  @override
  Duration nextRefresh(DateTime now) => const Duration(minutes: 30);
}

// Routes ---------------------------------------------------------------------------

typedef RoadStatus = LiveStatus<RoadReport>;

final roadsFetchProvider = Provider<Future<RoadReport> Function()>((ref) {
  final client = RoadsClient();
  ref.onDispose(client.close);
  return client.fetch;
});

final roadsProvider = AsyncNotifierProvider<RoadsNotifier, RoadStatus>(RoadsNotifier.new);

class RoadsNotifier extends LiveSource<RoadReport> {
  @override
  String get cacheKey => 'routes';

  @override
  bool get worksOnWeb => true;

  @override
  Future<RoadReport> fetch() => ref.read(roadsFetchProvider)();

  @override
  Map<String, Object?> encode(RoadReport value) => value.toJson();

  @override
  RoadReport decode(Map<String, Object?> json) => RoadReport.fromJson(json);

  @override
  Duration nextRefresh(DateTime now) => const Duration(minutes: 30);
}

// Bus en temps réel ------------------------------------------------------------------

final transitRealtimeFetchProvider = Provider<Future<TransitRealtime> Function()>((ref) {
  final client = TransitClient();
  ref.onDispose(client.close);
  return client.realtime;
});

/// Retards et avances de la STS, relus toutes les 30 secondes, seulement
/// quand l'adresse affichée a un arrêt. Rien n'est gardé : passé trois
/// minutes, un temps réel ne vaut plus rien.
final transitRealtimeProvider = AsyncNotifierProvider<TransitRealtimeNotifier, TransitRealtime?>(
  TransitRealtimeNotifier.new,
);

class TransitRealtimeNotifier extends AsyncNotifier<TransitRealtime?> {
  @override
  Future<TransitRealtime?> build() async {
    final hasStop = ref.watch(placeProvider.select((p) => p?.stop != null));
    if (!hasStop || kIsWeb) return null;
    final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
    try {
      return await ref.read(transitRealtimeFetchProvider)();
    } on Object catch (e) {
      debugPrint('Temps réel de la STS non lu : $e');
      return null;
    }
  }
}

/// Relit tout ce qui vient en direct, par exemple au retour au premier plan.
/// [read] est `ref.read`, d'un `Ref` comme d'un `WidgetRef`.
Future<void> refreshLiveSources(
  R Function<R>(ProviderListenable<R> provider) read, {
  bool force = false,
}) async {
  await Future.wait<void>([
    read(emergenciesProvider.notifier).refresh(force: force),
    read(weatherProvider.notifier).refresh(force: force),
    read(powerProvider.notifier).refresh(force: force),
    read(waterLayerProvider.notifier).refresh(force: force),
    read(roadworksLayerProvider.notifier).refresh(force: force),
    read(roadsProvider.notifier).refresh(force: force),
  ]);
}
