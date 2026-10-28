import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/colors.dart';
import 'addresses.dart';
import 'live_sources.dart';
import 'web_relay.dart';

/// Remplacé dans `main()` une fois les préférences chargées.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider doit être remplacé au démarrage'),
);

// Adresse ------------------------------------------------------------------

final placesProvider = Provider<List<Place>>((ref) => Demo.places);

final placeIdProvider = NotifierProvider<PlaceIdNotifier, String?>(PlaceIdNotifier.new);

class PlaceIdNotifier extends Notifier<String?> {
  static const _key = 'place';

  /// Une adresse qui n'existe plus (retirée d'une version, restaurée d'une
  /// vieille sauvegarde) est oubliée : on repasse par l'accueil plutôt que de
  /// rester devant un écran vide.
  @override
  String? build() {
    final saved = ref.watch(sharedPrefsProvider).getString(_key);
    if (saved == null) return null;
    final known =
        ref.watch(placesProvider).any((p) => p.id == saved) ||
        ref.watch(savedAddressesProvider).any((a) => a.id == saved);
    return known ? saved : null;
  }

  Future<void> choose(String id) async {
    state = id;
    await ref.read(sharedPrefsProvider).setString(_key, id);
  }

  Future<void> forget() async {
    state = null;
    await ref.read(sharedPrefsProvider).remove(_key);
  }
}

/// L'adresse choisie. C'est elle qui compte pour les rappels et le widget,
/// même pendant une démo.
///
/// Une adresse de démo est figée ; une vraie adresse est assemblée avec les
/// relevés en direct : son horaire de collecte, ses arrêts de bus, les avis
/// d'aqueduc dont la zone la couvre et les chantiers proches.
final savedPlaceProvider = Provider<Place?>((ref) {
  final id = ref.watch(placeIdProvider);
  if (id == null) return null;
  final demo = ref.watch(placesProvider).where((p) => p.id == id).firstOrNull;
  if (demo != null) return demo;
  final address = ref.watch(savedAddressesProvider).where((a) => a.id == id).firstOrNull;
  if (address == null) return null;
  return livePlace(
    address,
    collection: ref.watch(collectionScheduleProvider(id)).value,
    stop: ref.watch(stopScheduleProvider(id)).value,
    water: ref.watch(waterLayerProvider).value?.snapshot,
    roadworks: ref.watch(roadworksLayerProvider).value?.snapshot,
    // Dans un navigateur sans relais, le site de la Ville refuse la lecture.
    collectionMissingNote: kIsWeb && webRelay == null ? 'sur le téléphone seulement' : null,
  );
});

/// Les autres adresses gardées, sous leur nom : on veille sur elles aussi
/// (eau, pannes), sans qu'il faille les afficher.
final followedPlacesProvider = Provider<List<({Place place, String who})>>((ref) {
  final id = ref.watch(placeIdProvider);
  final water = ref.watch(waterLayerProvider).value?.snapshot;
  final works = ref.watch(roadworksLayerProvider).value?.snapshot;
  return [
    for (final a in ref.watch(savedAddressesProvider))
      if (a.id != id) (place: livePlace(a, water: water, roadworks: works), who: a.displayName),
  ];
});

/// L'horaire des collectes de l'adresse est-il encore en lecture ?
final placeLoadingProvider = Provider<bool>((ref) {
  final id = ref.watch(placeIdProvider);
  if (id == null || !id.startsWith('adr:')) return false;
  return ref.watch(collectionScheduleProvider(id)).isLoading;
});

/// L'adresse affichée : celle du moment rejoué en démo, sinon l'adresse choisie.
final placeProvider = Provider<Place?>((ref) {
  final moment = ref.watch(demoMomentProvider);
  if (moment != null && ref.watch(demoTimeProvider) != null) {
    final demo = ref.watch(placesProvider).where((p) => p.id == moment.placeId).firstOrNull;
    if (demo != null) return demo;
  }
  return ref.watch(savedPlaceProvider);
});

// Heure ----------------------------------------------------------------------

/// En démo, on peut figer l'heure sur un moment précis.
final demoTimeProvider = NotifierProvider<DemoTimeNotifier, DateTime?>(DemoTimeNotifier.new);

class DemoTimeNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? at) => state = at;
}

/// Le moment rejoué, avec son adresse et sa mise en situation éventuelle.
final demoMomentProvider = NotifierProvider<DemoMomentNotifier, DemoMoment?>(
  DemoMomentNotifier.new,
);

class DemoMomentNotifier extends Notifier<DemoMoment?> {
  @override
  DemoMoment? build() => null;

  void play(DemoMoment moment) {
    state = moment;
    ref.read(demoTimeProvider.notifier).set(moment.at);
  }

  void stop() {
    state = null;
    ref.read(demoTimeProvider.notifier).set(null);
  }
}

final _tickProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()),
);

/// L'heure affichée : la vraie, ou celle de la démo.
final nowProvider = Provider<DateTime>((ref) {
  final frozen = ref.watch(demoTimeProvider);
  if (frozen != null) return frozen;
  ref.watch(_tickProvider);
  return DateTime.now();
});

/// L'horloge réelle. Remplacée dans les tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Le vrai jour, même en démo : les notifications et le widget suivent le calendrier réel.
final realDayProvider = Provider<DateTime>((ref) {
  ref.watch(_tickProvider);
  return startOfDay(ref.watch(clockProvider)());
});

// Données ----------------------------------------------------------------------

/// Ce que l'app sait de la ville en ce moment : avis d'aqueduc, urgences,
/// météo, pannes, routes et bus arrivent en direct. Sans réseau, chaque source
/// retombe sur son dernier relevé, puis sur celui du 25 octobre 2026.
final liveCityProvider = Provider<CityData>((ref) {
  final water = ref.watch(waterLayerProvider).value?.snapshot;
  return CityData(
    waterNotices: water?.notices ?? Demo.waterNotices,
    waterKnownUntil: water?.knownUntil ?? Demo.city.waterKnownUntil,
    emergencies: ref.watch(emergenciesProvider).value?.snapshot ?? Demo.emergencies,
    weather: ref.watch(weatherProvider).value?.snapshot,
    power: ref.watch(powerProvider).value?.snapshot,
    roads: ref.watch(roadsProvider).value?.snapshot,
    transit: ref.watch(transitRealtimeProvider).value,
    air: ref.watch(airProvider).value?.snapshot,
    fireBans: ref.watch(fireBansProvider).value?.snapshot,
    peaks: ref.watch(peaksProvider).value?.snapshot,
  );
});

/// Ce qui s'affiche. Un moment rejoué apporte sa propre météo et ses pannes :
/// la météo d'aujourd'hui n'a rien à faire dans un soir de novembre.
final cityProvider = Provider<CityData>((ref) {
  final live = ref.watch(liveCityProvider);
  final moment = ref.watch(demoMomentProvider);
  if (moment == null || ref.watch(demoTimeProvider) == null) return live;
  // Les avis de la démo sont ceux du relevé du 25 octobre, comme le reste du moment.
  return CityData(
    waterNotices: Demo.waterNotices,
    waterKnownUntil: Demo.city.waterKnownUntil,
    emergencies: live.emergencies,
    weather: moment.weather,
    power: moment.power,
  );
});

const engine = RelevanceEngine();

final todayProvider = Provider<Today?>((ref) {
  final place = ref.watch(placeProvider);
  if (place == null) return null;
  return engine.today(place, ref.watch(cityProvider), ref.watch(nowProvider));
});

final weekProvider = Provider<Week?>((ref) {
  final place = ref.watch(placeProvider);
  if (place == null) return null;
  // Une fois par jour suffit : la semaine ne bouge pas d'une minute à l'autre.
  ref.watch(nowProvider.select(startOfDay));
  return const Agenda().week(place, ref.watch(cityProvider), ref.read(nowProvider));
});

// Couleurs ----------------------------------------------------------------------

final paletteProvider = NotifierProvider<PaletteNotifier, AppPalette>(PaletteNotifier.new);

class PaletteNotifier extends Notifier<AppPalette> {
  static const _key = 'palette';

  @override
  AppPalette build() {
    final saved = ref.watch(sharedPrefsProvider).getString(_key);
    return AppPalette.values.where((p) => p.name == saved).firstOrNull ??
        AppPalette.saguenayAujourdhui;
  }

  Future<void> choose(AppPalette palette) async {
    state = palette;
    await ref.read(sharedPrefsProvider).setString(_key, palette.name);
  }
}

// Heures calmes ------------------------------------------------------------------

/// De 22 h à 7 h, les alertes attendent le matin, sauf un avis d'ébullition.
final quietHoursProvider = NotifierProvider<QuietHoursNotifier, bool>(QuietHoursNotifier.new);

class QuietHoursNotifier extends Notifier<bool> {
  static const key = 'heures-calmes';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(key) ?? false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(key, on);
  }
}

// Rappels ----------------------------------------------------------------------

extension ReminderLabels on ReminderKind {
  String get title => switch (this) {
    ReminderKind.water => 'Avis d’eau à mon adresse',
    ReminderKind.weather => 'Alertes météo',
    ReminderKind.power => 'Coupures de courant planifiées',
    ReminderKind.parking => 'Stationnement de nuit',
    ReminderKind.collection => 'Collecte',
    ReminderKind.roadwork => 'Travaux sur ma rue',
    ReminderKind.week => 'Ma semaine',
    ReminderKind.peak => 'Pointes d’Hydro-Québec',
  };

  String get when => switch (this) {
    ReminderKind.water => 'Dès que l’app voit un avis',
    ReminderKind.weather => 'Avertissements et veilles d’Environnement Canada',
    ReminderKind.power => 'La veille, à 19 h',
    ReminderKind.parking => 'Les soirs d’hiver, à 21 h',
    ReminderKind.collection => 'La veille, à 19 h',
    ReminderKind.roadwork => 'Les matins de semaine, à 6 h 45',
    ReminderKind.week => 'Le dimanche, à 18 h',
    ReminderKind.peak => 'La veille : utile avec le Crédit hivernal ou Flex D',
  };
}

final remindersProvider = NotifierProvider<RemindersNotifier, Set<ReminderKind>>(
  RemindersNotifier.new,
);

class RemindersNotifier extends Notifier<Set<ReminderKind>> {
  static const _key = 'reminders';

  static const defaults = {
    ReminderKind.water,
    ReminderKind.weather,
    ReminderKind.power,
    ReminderKind.parking,
    ReminderKind.collection,
    ReminderKind.week,
  };

  @override
  Set<ReminderKind> build() => read(ref.watch(sharedPrefsProvider));

  /// Aussi lu par la tâche de fond, qui n'a pas Riverpod.
  static Set<ReminderKind> read(SharedPreferences prefs) {
    final saved = prefs.getStringList(_key);
    if (saved == null) return defaults;
    return {for (final name in saved) ...ReminderKind.values.where((r) => r.name == name)};
  }

  Future<void> toggle(ReminderKind r, bool on) async {
    state = on ? {...state, r} : ({...state}..remove(r));
    await ref.read(sharedPrefsProvider).setStringList(_key, [for (final r in state) r.name]);
  }
}
