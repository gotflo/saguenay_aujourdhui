import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';
import 'web_relay.dart';

/// Recherche et confirmation d'adresse. Remplacé dans les tests.
final addressClientProvider = Provider<AddressClient>((ref) {
  final client = AddressClient();
  ref.onDispose(client.close);
  return client;
});

/// Les adresses ajoutées par l'utilisateur (maison, travail, parents...).
final savedAddressesProvider = NotifierProvider<SavedAddresses, List<ResolvedAddress>>(
  SavedAddresses.new,
);

class SavedAddresses extends Notifier<List<ResolvedAddress>> {
  static const key = 'adresses';

  @override
  List<ResolvedAddress> build() => readSavedAddresses(ref.watch(sharedPrefsProvider));

  Future<void> add(ResolvedAddress a) async {
    state = [...state.where((x) => x.id != a.id), a];
    await _save();
  }

  /// Retire l'adresse. Si c'était celle affichée, on passe à une autre.
  Future<void> remove(String id) async {
    state = [...state.where((x) => x.id != id)];
    await _save();
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove('collecte:$id');
    await prefs.remove('bus:$id');
    if (ref.read(placeIdProvider) == id) {
      final next = state.lastOrNull;
      if (next == null) {
        await ref.read(placeIdProvider.notifier).forget();
      } else {
        await ref.read(placeIdProvider.notifier).choose(next.id);
      }
    }
  }

  Future<void> _save() => ref.read(sharedPrefsProvider).setStringList(key, [
    for (final a in state) jsonEncode(a.toJson()),
  ]);
}

/// Lit les adresses gardées ; une entrée abîmée est ignorée.
List<ResolvedAddress> readSavedAddresses(SharedPreferences prefs) => [
  for (final raw in prefs.getStringList(SavedAddresses.key) ?? const <String>[]) ?_decode(raw),
];

ResolvedAddress? _decode(String raw) {
  try {
    return ResolvedAddress.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
  } on Object {
    return null;
  }
}

// Horaire des collectes -------------------------------------------------------------

/// Lit l'horaire des collectes d'une adresse auprès de la Ville. Remplacé dans les tests.
final collectionFetchProvider = Provider<Future<CollectionSchedule> Function(ResolvedAddress)>((
  ref,
) {
  final client = CollectionClient(client: sourceClient());
  ref.onDispose(client.close);
  return client.schedule;
});

/// L'horaire d'une adresse : gardé sur le téléphone, relu une fois par semaine.
/// `null` tant qu'on n'a jamais pu le lire.
final collectionScheduleProvider =
    AsyncNotifierProvider.family<CollectionScheduleNotifier, CollectionSchedule?, String>(
      CollectionScheduleNotifier.new,
    );

class CollectionScheduleNotifier extends AsyncNotifier<CollectionSchedule?> {
  CollectionScheduleNotifier(this.id);

  final String id;

  @override
  Future<CollectionSchedule?> build() async {
    final address = ref.watch(savedAddressesProvider).where((a) => a.id == id).firstOrNull;
    if (address == null) return null;
    final prefs = ref.read(sharedPrefsProvider);
    final cached = readCached(prefs, 'collecte:$id', CollectionSchedule.fromJson);
    if (cached != null && cached.$1.isAfter(DateTime.now().subtract(const Duration(days: 7)))) {
      return cached.$2;
    }
    // Sans relais, un navigateur ne peut pas lire le site de la Ville.
    if (kIsWeb && webRelay == null) return cached?.$2;
    try {
      final schedule = await ref.read(collectionFetchProvider)(address);
      await writeCached(prefs, 'collecte:$id', schedule.toJson());
      return schedule;
    } on Object catch (e) {
      debugPrint('Collectes non lues : $e');
      return cached?.$2;
    }
  }
}

// Bus -------------------------------------------------------------------------------

/// Télécharge le flux GTFS de la STS. Remplacé dans les tests.
final gtfsFetchProvider = Provider<Future<Uint8List> Function()>((ref) {
  final client = TransitClient();
  ref.onDispose(client.close);
  return client.gtfs;
});

/// L'horaire des arrêts les plus proches d'une adresse, pour trois semaines.
/// Le flux pèse 700 Ko : on le lit une fois par semaine, dans un isolat.
final stopScheduleProvider =
    AsyncNotifierProvider.family<StopScheduleNotifier, StopSchedule?, String>(
      StopScheduleNotifier.new,
    );

class StopScheduleNotifier extends AsyncNotifier<StopSchedule?> {
  StopScheduleNotifier(this.id);

  final String id;

  @override
  Future<StopSchedule?> build() async {
    final address = ref.watch(savedAddressesProvider).where((a) => a.id == id).firstOrNull;
    if (address == null) return null;
    final prefs = ref.read(sharedPrefsProvider);
    final cached = readCached(prefs, 'bus:$id', StopSchedule.fromJson);
    final now = DateTime.now();
    if (cached != null &&
        cached.$1.isAfter(now.subtract(const Duration(days: 7))) &&
        cached.$2.validTo.isAfter(now.add(const Duration(days: 7)))) {
      return cached.$2;
    }
    // Le serveur de la STS n'autorise pas les navigateurs.
    if (kIsWeb) return cached?.$2;
    try {
      final zip = await ref.read(gtfsFetchProvider)();
      final (lat, lon) = (address.lat, address.lon);
      final schedule = await _inBackground(zip, lat, lon, now);
      if (schedule == null) return null;
      await writeCached(prefs, 'bus:$id', schedule.toJson());
      return schedule;
    } on Object catch (e) {
      debugPrint('Horaire du bus non lu : $e');
      return cached?.$2;
    }
  }
}

/// Dans une fonction à part : la fermeture n'emporte que ces valeurs vers l'isolat.
Future<StopSchedule?> _inBackground(Uint8List zip, double lat, double lon, DateTime now) =>
    Isolate.run(() => stopScheduleFor(zip, lat, lon, from: now, days: 21));

// Relevés gardés ----------------------------------------------------------------------

/// Un relevé gardé et sa date, ou `null` s'il manque ou s'il est abîmé.
(DateTime, T)? readCached<T>(
  SharedPreferences prefs,
  String key,
  T Function(Map<String, Object?>) decode,
) {
  final raw = prefs.getString(key);
  if (raw == null) return null;
  try {
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    return (
      DateTime.parse(json['at'] as String),
      decode((json['value'] as Map).cast<String, Object?>()),
    );
  } on Object {
    unawaited(prefs.remove(key));
    return null;
  }
}

Future<void> writeCached(SharedPreferences prefs, String key, Map<String, Object?> value) =>
    prefs.setString(key, jsonEncode({'at': DateTime.now().toIso8601String(), 'value': value}));
